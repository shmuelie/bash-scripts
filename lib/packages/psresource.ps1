# Bridge to Shmuelie.Utilities PSResourceHelpers.ps1; no local metadata parser.
[CmdletBinding(SupportsShouldProcess)]
param()

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Invoke-Canonical {
    param([scriptblock] $Action)
    & $Action 3>&1 | ForEach-Object {
        if ($_ -is [System.Management.Automation.WarningRecord]) {
            [Console]::Error.WriteLine("Warning: $($_.Message)")
            $script:Warnings.Add($_.Message)
        } else { $_ }
    }
}

function Get-Resources {
    param([string] $Path, [string[]] $Name, [string[]] $Exclude)
    Invoke-Canonical {
        & $script:Utilities {
            param($Path, $Name, $Exclude)
            Get-InstalledPSResourceInPath -Path $Path -Name $Name -Exclude $Exclude -ErrorAction Stop
        } $Path $Name $Exclude
    }
}

try {
    $request = [Console]::In.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop
    if ($request.operation -notin @('Probe', 'Discover', 'Update')) { throw 'Invalid bridge operation.' }
    $script:Warnings = [System.Collections.Generic.List[string]]::new()
    $missing = @()
    foreach ($moduleName in @('Shmuelie.Utilities', 'Microsoft.PowerShell.PSResourceGet')) {
        if (-not (Get-Module -ListAvailable -Name $moduleName)) { $missing += $moduleName }
    }
    if ($missing.Count) {
        if ($request.operation -ne 'Probe') { throw "Missing canonical dependencies: $($missing -join ', ')" }
        [Console]::Out.WriteLine((@{available = $false; reason = "Missing canonical dependencies: $($missing -join ', ')"} | ConvertTo-Json -Compress))
        exit 0
    }
    Invoke-Canonical { Import-Module Shmuelie.Utilities, Microsoft.PowerShell.PSResourceGet -ErrorAction Stop }
    $updater = Get-Command 'Shmuelie.Utilities\Update-InstalledPSResource' -ErrorAction Ignore
    $script:Utilities = if ($updater) { $updater.Module } else { $null }
    $compatible = $null -ne $script:Utilities
    foreach ($command in @('Find-PSResource', 'Save-PSResource', 'Get-PSResourceRepository')) {
        if (-not (Get-Command "Microsoft.PowerShell.PSResourceGet\$command" -ErrorAction Ignore)) { $compatible = $false }
    }
    if ($compatible) {
        $compatible = & $script:Utilities {
            foreach ($name in @('Get-InstalledPSResourceInPath', 'Compare-PSResourceVersion')) {
                if (-not (Get-Command $name -CommandType Function -ListImported -ErrorAction Ignore)) { return $false }
            }
            return $true
        }
    }
    if ($request.operation -eq 'Probe') {
        [Console]::Out.WriteLine((@{available = [bool]$compatible; reason = 'Requires compatible Shmuelie.Utilities resource discovery and comparison helpers.'} | ConvertTo-Json -Compress))
        exit 0
    }
    if (-not $compatible) { throw 'Unsupported canonical Utilities version.' }
    $options = $request.options
    if ($request.operation -eq 'Discover') {
        $targets = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($root in $options.roots) {
            if (-not (Test-Path -LiteralPath $root -PathType Container)) {
                $targets.Add(@{target = $root; skipReason = 'Configured module root is unavailable.'})
                continue
            }
            $resolved = Resolve-Path -LiteralPath $root
            if ($resolved.Provider.Name -ne 'FileSystem') { throw 'Module roots must be filesystem directories.' }
            $path = $resolved.ProviderPath
            if (-not $seen.Add($path)) { continue }
            foreach ($resource in @(Get-Resources $path $options.name $options.exclude)) {
                if ([string]::IsNullOrWhiteSpace($resource.Name) -or $resource.Name.Contains(',')) {
                    throw 'Canonical resource name cannot be individually selected.'
                }
                if ([string]::IsNullOrWhiteSpace($resource.Version)) { throw 'Canonical discovery returned an unknown version.' }
                $targets.Add(@{
                    target = Join-Path $path $resource.Name
                    path = $path
                    name = $resource.Name
                    version = [string]$resource.Version
                    proposedVersion = $null
                })
            }
        }
        [Console]::Out.WriteLine((ConvertTo-Json -InputObject @($targets.ToArray()) -Depth 12 -Compress))
        exit 0
    }
    $target = $request.target
    $name = [System.Management.Automation.WildcardPattern]::Escape($target.name)
    $before = @(Get-Resources $target.path @($name) @())
    if ($before.Count -ne 1 -or $before[0].Version -cne $target.version) {
        throw 'Installed resource changed since discovery; run discovery again.'
    }
    if (-not $PSCmdlet.ShouldProcess($target.target, 'Update canonical installed PowerShell resource')) {
        [Console]::Out.WriteLine((@{status = 'Skipped'; resultingVersion = $before[0].Version; reason = 'Not approved.'} | ConvertTo-Json -Compress))
        exit 0
    }
    $parameters = @{Path = $target.path; Name = $name; Confirm = $false; ErrorAction = 'Stop'}
    if ($options.repository) { $parameters.Repository = $options.repository }
    $script:Warnings.Clear()
    Invoke-Canonical { Shmuelie.Utilities\Update-InstalledPSResource @parameters } | Out-Null
    $after = @(Get-Resources $target.path @($name) @())
    if ($after.Count -ne 1) { throw 'Could not observe the updated installed resource.' }
    $comparison = & $script:Utilities {
        param($Left, $Right)
        Compare-PSResourceVersion -Left $Left -Right $Right
    } $after[0] $before[0]
    if ($comparison -lt 0) { throw 'The canonical installed resource version decreased.' }
    $status = if ($comparison -gt 0) { 'Updated' } elseif ($script:Warnings.Count) { 'Skipped' } else { 'Unchanged' }
    $reason = if ($script:Warnings.Count) { $script:Warnings -join [Environment]::NewLine }
        elseif ($comparison -eq 0) { 'No newer version observed; the canonical helper does not distinguish current resources from silent repository skips.' }
        else { $null }
    [Console]::Out.WriteLine((@{status = $status; resultingVersion = [string]$after[0].Version; reason = $reason} | ConvertTo-Json -Compress))
} catch {
    [Console]::Error.WriteLine($_.ToString())
    exit 1
}
