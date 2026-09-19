function Get-InstalledPSResourceInPath {
    param($Path, $Name, $Exclude)
    Add-Content -LiteralPath $env:CALL_LOG -Value "discover:$Path"
    if ($Name -and -not (@($Name | Where-Object { 'Demo' -like $_ }).Count)) { return }
    if (@($Exclude | Where-Object { $_ -and 'Demo' -like $_ }).Count) { return }
    $fixture = Get-Content -LiteralPath $env:RESOURCE_FIXTURE -Raw | ConvertFrom-Json
    $version = if (Test-Path -LiteralPath $env:RESOURCE_UPDATED) { $fixture.after } else { $fixture.before }
    [pscustomobject]@{Name = 'Demo'; Version = $version; Repository = $fixture.repository}
}

function Compare-PSResourceVersion {
    param($Left, $Right)
    Add-Content -LiteralPath $env:CALL_LOG -Value "compare:$($Right.Version):$($Left.Version)"
    $fixture = Get-Content -LiteralPath $env:RESOURCE_FIXTURE -Raw | ConvertFrom-Json
    return $fixture.comparison
}

function Update-InstalledPSResource {
    [CmdletBinding(SupportsShouldProcess)]
    param($Path, $Name, $Repository)
    Add-Content -LiteralPath $env:CALL_LOG -Value "update:$Path|$Name|$Repository"
    if ($env:RESOURCE_FAIL -eq '1') { throw 'canonical update failure' }
    if ($env:RESOURCE_WARN -eq '1') { Write-Warning 'canonical repository warning' }
    if ($PSCmdlet.ShouldProcess($Path, 'Synthetic update')) {
        Set-Content -LiteralPath $env:RESOURCE_UPDATED -Value updated
    }
}

Export-ModuleMember -Function Update-InstalledPSResource
