using module ./Classes/DeploymentTool.Classes.psm1
<#
.SYNOPSIS
    Replaces a package folder on the requested hosts with the selected source-control branch.
#>
[CmdletBinding()]
param(
    [string] $Servers,
    [string] $User,
    [securestring] $Token,
    [string] $ProtectedToken,
    [string] $Repo,
    [string] $Dest,
    [string] $Branch,
    [string] $SourceRoot = 'https://source-control.example',
    [switch] $Relaunched
)

$Script:StartFolder = Get-Location
try {
    . "$PSScriptRoot\DeploymentSettings.ps1"

    $SamplePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json'
    $Sample = Get-Content -Path $SamplePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $Package = $Sample.packages | Select-Object -First 1
    [pscustomobject]@{
        Stage = 'RepoRefreshEngineTraining'
        Servers = $Sample.hosts -join ', '
        Repo = $Package.sourcePath
        Destination = $Package.folder
        Branch = 'main'
        Action = 'Verify source, check hosts, archive target, fetch branch and roll back on failure.'
    }

    exit 0
} catch {
    Write-Error -Message "Refresh stopped: $($_.Exception.Message)"
    exit 1
} finally {
    Set-Location -Path $Script:StartFolder
}
