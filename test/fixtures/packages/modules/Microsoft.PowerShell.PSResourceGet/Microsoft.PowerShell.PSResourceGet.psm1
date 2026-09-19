# The bridge must leave repository operations to the canonical updater.
function Find-PSResource { throw 'Unexpected repository query' }
function Save-PSResource { throw 'Unexpected repository mutation' }
function Get-PSResourceRepository { throw 'Unexpected repository query' }
Export-ModuleMember -Function Find-PSResource, Save-PSResource, Get-PSResourceRepository
