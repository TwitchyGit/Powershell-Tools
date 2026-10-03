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
        $Env = Read-Host -Prompt 'Environment (NONPROD, PROD)'
    }

    if ($null -eq $ServiceCredential) {
        $ServiceCredential = Get-Credential -Message 'Service account for this environment'
    }

    if ($null -eq $AdministratorCredential) {
        $AdministratorCredential = Get-Credential -Message 'Credential vault administrator account'
    }

    $Profile = Get-EnvironmentProfile -Env $Env
    $Packages = Get-CheckedCatalogue -RepoName $RepoName
    $BackupServiceAccount = $ServiceCredential.UserName
    if ($Profile.Name -ne 'PROD') {
        $BackupServiceAccount = 'backup-service'
    }

    Write-Output "Environment: $($Profile.Name)"
    Write-Output "Service account: $($ServiceCredential.UserName)"
    Write-Output "Backup service account: $BackupServiceAccount"
    Write-Output "Packages: $(($Packages.Name) -join ', ')"
    $null = Read-Host -Prompt 'Press return to continue'

    $Configurator = [DeploymentConfigurator]::new(
        $Profile,
        $Packages,
        $ServiceCredential,
        $AdministratorCredential,
        $BackupServiceAccount
    )
    exit $Configurator.Run()
} catch {
    Write-Error -Message "Configurator stopped: $($_.Exception.Message)"
    exit 1
} finally {
    Set-Location -Path $Script:StartFolder
}
