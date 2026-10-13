using module ./Classes/DeploymentTool.Classes.psm1
<#
.SYNOPSIS
    Collects refresh choices and calls the refresh engine once per selected package.
#>
[CmdletBinding()]
param(
    [ValidateSet('NONPROD', 'PROD')]
    [string] $Env,
    [string] $GitUser,
    [securestring] $GitToken,
    [string] $FailoverHost,
    [string[]] $RepoName,
    [switch] $RemoveToken,
    [string] $SourceRoot = 'https://source-control.example'
)

$Script:StartFolder = Get-Location
try {
    . "$PSScriptRoot\DeploymentSettings.ps1"

    if ([string]::IsNullOrWhiteSpace($Env)) {
        $Env = 'NONPROD'
    }

    $Profile = Get-EnvironmentProfile -Env $Env
    $SamplePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json'
    $Sample = Get-Content -Path $SamplePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $Packages = foreach ($Package in $Sample.packages) {
        [pscustomobject]@{
            Name = $Package.name
            SourcePath = $Package.sourcePath
            Folder = $Package.folder
        }
    }
    if ($RepoName -and $RepoName.Count -gt 0) {
        $Packages = $Packages | Where-Object { $_.Name -in $RepoName }
    }

    foreach ($Package in $Packages) {
        [pscustomobject]@{
            Stage = 'RepoRefreshTraining'
            Environment = $Profile.Name
            Branch = $Profile.Branch
            HostList = $Sample.hosts -join ', '
            Package = $Package.Name
            SourcePath = $Package.SourcePath
            Destination = $Package.Folder
            Action = 'Validate, inspect status, refresh from source and restore on failure.'
        }
    }

    exit 0
} catch {
    Write-Error -Message "Launcher stopped: $($_.Exception.Message)"
    exit 1
} finally {
    Set-Location -Path $Script:StartFolder
}
