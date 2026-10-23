<#
.SYNOPSIS
    Interactive front end that collects credentials and applies environment-specific setup to the refreshed
    packages
#>

#Requires -RunAsAdministrator
#Requires -Version 7.6

[CmdletBinding()]
param(
    [ValidateSet('ENG', 'DEV', 'PROD')][string]$Env,
    [string[]]$RepoName,
    [PSCredential]$ServiceCredential,
    [PSCredential]$AdminUser
)

$BaseDir       = $PSScriptRoot
$StartLocation = Get-Location
$FailStatus    = 0

try {
    Import-Module -Name (Join-Path -Path $BaseDir -ChildPath 'Config\Configure-Settings.psm1') -Force -ErrorAction Stop
    $null = Resolve-RepoDeployment -RepoName $RepoName
} catch {
    Write-Error -Message "Unable to load the Config module or validate -RepoName: $($_.Exception.Message)" `
        -ErrorAction Continue
    exit 1
}

if (-not $Env) {
    Write-Output "`nQuestion: Environment"
    while (-not $Env) {
        $Answer = (Read-Host -Prompt "Confirm environment - ENG, DEV, PROD").Trim().ToUpper()
        if ($Answer -in 'ENG', 'DEV', 'PROD') {
            $Env = $Answer
        } else {
            Write-Output "Invalid environment"
        }
    }
}

if (-not $ServiceCredential) {
    $ServiceCredential = Get-Credential -Message "Provide the OS Service Account for this environment"
}
if (-not $AdminUser) {
    $AdminUser = Get-Credential -Message "Provide the CyberArk Admin user/password"
}
# ServiceCredential must be DOMAIN\account or account@domain for the SetCred logon, AdminUser is used as entered
$ServiceUser  = $ServiceCredential.UserName
$IsDomainUser = $ServiceUser -match '^[A-Za-z0-9._-]+\\[^\\/\s@]+$'
$IsUpn        = $ServiceUser -match '^[^@\\\s]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$'
if (-not ($IsDomainUser -or $IsUpn)) {
    Write-Error -Message ("-ServiceCredential user name must be DOMAIN\account or account@domain. " +
        "Value was '$ServiceUser'") -ErrorAction Continue
    exit 1
}

# SetConfig scripts get the bare account name, SetCred logs on with the full ServiceCredential
$ServiceAccount       = $ServiceCredential.UserName -replace '^.*\\', '' -replace '@.*$', ''
# PROD backs up with the service account, other environments use the fixed account1
$ServiceAccountBackup = if ($Env -eq 'PROD') { $ServiceAccount } else { 'account1' }

$Settings = Get-EnvSettings -Env $Env
$RepoNameText = if ($RepoName) { ($RepoName -join ',') } else { 'All' }

Write-Output "`nThis will run the configuration on any servers as follows:"
Write-Output "  Env                = $Env"
Write-Output "  RepoName           = $RepoNameText"
Write-Output "  ServiceCredential  = $($ServiceCredential.UserName)"
Write-Output "  CyberarkAdmin      = $($AdminUser.UserName)"
Write-Output "  ServiceAccount     = $ServiceAccount"
Write-Output "  PACLIVersion       = $($Settings.PACLIVersion)"
Write-Output "  PADRVersion        = $($Settings.PADRVersion)"
Write-Output "  EVDVersion         = $($Settings.EVDVersion)"
Write-Output "  BackupPool         = $($Settings.BackupPool)"

Read-Host -Prompt "Enter Yes to continue, or Ctrl-C to stop"

try {
    # Account names are strings, ServiceCredential and AdminUser stay PSCredentials
    $ConfigureParams = @{
        Env                  = $Env
        ServiceAccount       = $ServiceAccount
        ServiceAccountBackup = $ServiceAccountBackup
        ServiceCredential    = $ServiceCredential
        AdminUser            = $AdminUser
        RepoName             = $RepoName
    }
    Invoke-Configure @ConfigureParams
} catch {
    Write-Error -Message "Configure failed for ${Env}: $($_.Exception.Message)" -ErrorAction Continue
    $FailStatus = 1
}

Remove-Variable -Name ServiceCredential, AdminUser, ServiceAccount, ServiceAccountBackup
Set-Location -LiteralPath $StartLocation

exit $FailStatus
