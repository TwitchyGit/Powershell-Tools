using module ./Classes/DeploymentTool.Classes.psm1
<#
.SYNOPSIS
    Collects setup credentials and applies the package configuration recipes.
#>
[CmdletBinding()]
param(
    [ValidateSet('NONPROD', 'PROD')]
    [string] $Env,
    [string[]] $RepoName,
    [pscredential] $ServiceCredential,
    [pscredential] $AdministratorCredential
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
    $Packages = $Sample.packages
    if ($RepoName -and $RepoName.Count -gt 0) {
        $Packages = $Packages | Where-Object { $_.name -in $RepoName }
    }

    foreach ($Package in $Packages) {
        [pscustomobject]@{
            Stage = 'DeploymentConfigurationTraining'
            Environment = $Profile.Name
            ServiceAccount = 'svc-training-nonprod'
            BackupServiceAccount = 'backup-service'
            Package = $Package.name
            Action = 'Apply setup recipe with synthetic credentials and no live remoting.'
        }
    }

    exit 0
} catch {
    Write-Error -Message "Configurator stopped: $($_.Exception.Message)"
    exit 1
} finally {
    Set-Location -Path $Script:StartFolder
}
