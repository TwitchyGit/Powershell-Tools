<#
.SYNOPSIS
    Powershell module handling variables for powershell scripts

.DESCRIPTION
    Script : Cyb-User-Onboarding\Config\ConfigModule.psm1
    Source :
    Dist To: Server managing CyberArk User Onboarding

.EXAMPLE
    This is an import module

.OUTPUTS
    Variables functions returned in the Export-ModuleMember section.
#>

# Load System.Web assembly for URL encoding
Add-Type -AssemblyName System.Web

# Force TLS 1.2 and avoid small-request delays in Windows PowerShell 5.1.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::Expect100Continue = $false
[Net.ServicePointManager]::UseNagleAlgorithm = $false
# Keep revocation behaviour unchanged until the PVWA certificate policy is confirmed.
[Net.ServicePointManager]::CheckCertificateRevocationList = $false
# For Invoke-RestMethod - Bypass certificate validation (allows self-signed and expired certs)
[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

# Set directory where local config files are stored
$Script:BaseReportsDir  = "D:\Reports"
$Script:BaseLogsDir     = "D:\Logs"
$Script:BaseLocalConfig = "D:\Reports-LocalConfig"

# Define which environment is being called, this is set in Set-Configuration.ps1
if (Test-Path -Path "${BaseLocalConfig}\Environment.cfg") {
    Set-Variable -Name Environment -Value (Get-Content -Path ${BaseLocalConfig}\Environment.cfg)
    $Environment = $Environment.Trim()
} else {
    Write-Host "ERROR: ${BaseLocalConfig}\Environment.cfg not setup"
    return $false
}

# Define which service-account is used, this is set in Set-Configuration.ps1
if (Test-Path -Path "${BaseLocalConfig}\ServiceOwner.cfg") {
    Set-Variable -Name ConfRUNUSER -Value (Get-Content -Path ${BaseLocalConfig}\ServiceOwner.cfg)
    $ConfRUNUSER = $ConfRUNUSER.Trim()
} else {
    Write-Host "ERROR: ${BaseLocalConfig}\ServiceOwner.cfg not setup"
    return $false
}

# Check the directory of the script used to run the Import-Module, also allow invocation from command line.
# Its not where ConfigModule.ps1 resides, so cannot use $MyInvocation.
$CallStack = Get-PSCallStack
$CallFromScript = $false
$ScriptInfo = ( $CallStack | Where-Object { $_.ScriptName -and $_.ScriptName -notlike "*.psm1" } | `
        Select-Object -First 1).ScriptName
if ($ScriptInfo) { $CallFromScript = $true }

# Verify if called from script or command line for testing
if ($CallFromScript) {
    $setReportDir     = Split-Path (Split-Path $ScriptInfo -Parent) -Leaf
    $setReportFullDir = Split-Path -Parent $ScriptInfo
    $ReportName       = [System.IO.Path]::GetFileNameWithoutExtension($ScriptInfo)
} else {
    $setReportFullDir = (Get-Location).Path
    $setReportDir     = Split-Path $setReportFullDir -Leaf
    $ReportName       = "RunFromCLI"
}

# Set report locations
if ($setReportDir -like "Reports_*" -Or $setReportDir -like "Install" -Or $setReportDir -like "User_Recovery" -Or $setReportDir -like "Utilities" -Or $setReportDir -like "Cyb-User-Onboarding") {
    Set-Variable -Name ConfDirLogs      -Value "${BaseLogsDir}\${setReportDir}\"
    Set-Variable -Name ConfDirRepGen    -Value "${BaseLogsDir}\${setReportDir}_ReportGen\"
    $DirName = $setReportDir -replace 'Reports_', ''
    Set-Variable -Name ConfLogFile      -Value "${ConfDirLogs}\Log_${DirName}_${ReportName}.log"
    Set-Variable -Name ConfDirFiles     -Value (Join-Path $setReportFullDir "")
} else {
    Write-Host "ERROR: Must be run from a ${BaseReportsDir} subdirectory. Current directory: $setReportDir"
    return $false
}

# Log Directories
Set-Variable -Name ConfPlatfrmLogs     -Value "${BaseLogsDir}\Reports_Platforms"
Set-Variable -Name ConfIACOnbdLogs     -Value "${BaseLogsDir}\Reports_IACOnboarding"
Set-Variable -Name ConfUsersLogs       -Value "${BaseLogsDir}\Reports_Users"
Set-Variable -Name ConfADLogs          -Value "${BaseLogsDir}\Reports_ADGroups"
Set-Variable -Name ConfVaultFile       -Value "${BaseLocalConfig}\Vault.ini"
Set-Variable -Name ConfEnvFile         -Value "${BaseLocalConfig}\Environment.cfg"

# Credential required for Reports_Accounts
Set-Variable -Name ConfUserAccount       -Value "cs_Report_Accounts"
Set-Variable -Name ConfAccountCredFile   -Value "${BaseLocalConfig}\cs_Report_Accounts.ini"

# Credential required for Reports_Users
Set-Variable -Name ConfUserUsers         -Value "cs_Report_Users"
Set-Variable -Name ConfUserCredFile      -Value "${BaseLocalConfig}\cs_Report_Users.ini"

# Credential required for Reports_IACOnboarding
Set-Variable -Name ConfUsersSafes        -Value "cs_Report_Safes"
Set-Variable -Name ConfSafesCredFile     -Value "${BaseLocalConfig}\cs_Report_Safes.ini"


# Define variables based on runtime environment
if ($Environment -match "PROD") {
    Set-Variable -Name ConfSUPPORTENV   -Value "PROD"
    Set-Variable -Name ConfPVWAURL      -Value "https://pvwa-url-prod/PasswordVault/"
    Set-Variable -Name ConfDestDrive    -Value "\\dfsdrive\Data"
    Set-Variable -Name ConfVaultName    -Value "PRODVAULT"
    Set-Variable -Name ConfVaultAddr    -Value "cyberarkprod.com"
    Set-Variable -Name ConfADAccessGrp  -Value @("PROD\cyberark-group-1")

} elseif ($Environment -match "DEV") {
    Set-Variable -Name ConfSUPPORTENV   -Value "DEV"
    Set-Variable -Name ConfPVWAURL      -Value "https://pvwa-url-dev/PasswordVault/"
    Set-Variable -Name ConfDestDrive    -Value "\\dfsdrive\Data"
    Set-Variable -Name ConfDestDrive    -Value "\\eun047046.qaeurope.nom\C$\Temp\Logs"
    Set-Variable -Name ConfVaultName    -Value "PRODVAULT"
    Set-Variable -Name ConfVaultAddr    -Value "cyberarkdev.com"
    Set-Variable -Name ConfADAccessGrp  -Value @("DEV\cyberark-group-1")

} else {
    Write-Host "ERROR: Environment.cfg must contain one of PROD or DEV"
    return $false
}

# This must handle multiple arguments - Set domain search list, per environment
if ($ConfSUPPORTENV -in @("PROD")) {
    $ADDomainList = "PROD.NOM"
} else {
    $ADDomainList = "DEV.NOM"
}
Set-Variable -Name ADDomainList -Value $ADDomainList -Scope Global

# --- Onboarding-only settings ---------------------------------------------
# Not part of the gold-standard Reports config above, but required by the
# Cyb-User-Onboarding scripts. Renamed to the Conf* convention so every
# setting in this module follows one naming scheme.

$Script:CybLegacyConfigurationModulePath = 'C:\Scripts\Config\Configuration.psm1'
Set-Variable -Name ConfLegacyConfigurationModulePath -Value $Script:CybLegacyConfigurationModulePath
Set-Variable -Name ConfADConfigurationModuleName     -Value 'Configuration.psm1'
Set-Variable -Name ConfSafeScanLogPath               -Value 'D:\Logs\Scan-AllObjectsInSafes.log'

# Store suffixes separately so callers can apply one normalized PVWA base URL.
Set-Variable -Name ConfPVWAEndpointSuffixes -Value @{
    Authentication = 'API/auth/Cyberark/Logon/'
    Accounts       = 'API/Accounts/'
    Users          = 'API/Users?ExtendedDetails=true'
    Safes          = 'API/Safes/'
}

# Hide internal and system groups from human-user membership results.
Set-Variable -Name ConfUserInformationExcludedGroupPatterns -Value @(
    'PVWAUser1'
    'DR*'
    'VaultUser1'
    'Member*'
)

# Keep assignment feed locations consistent across onboarding scripts.
Set-Variable -Name ConfUserGroupAssignmentConfig -Value @{
    SafeFeedPath = 'C:\safe_feed.csv'
    UserFeedPath = 'C:\users.txt'
    OutputPath   = 'C:\output_feed.csv'
}

# Exclude service-style names before the more expensive human-user processing.
Set-Variable -Name ConfHumanUserScanConfig -Value @{
    Domains = @(
        'domain1.corp.local'
        'domain2.corp.local'
        'domain3.corp.local'
    )
    ExcludePatterns = @(
        '^adm-'
        '^svc-'
        '^svc_'
        '^sa-'
        '^sa_'
        '^test'
        '\$'
    )
    OutputDirectory = 'C:\Temp'
}

# Domains and target groups scanned by Find-ADUserDisabledInGroup.ps1.
# ConfADGroups has no equivalent elsewhere in this module - fill in the real
# nested-membership group names for this environment before first use.
Set-Variable -Name ConfADDomains -Value @($ConfHumanUserScanConfig.Domains)
Set-Variable -Name ConfADGroups  -Value @(
    'REPLACE-ME-group-1'
    'REPLACE-ME-group-2'
)

# Keep mutable API state inside the importing function module.
Set-Variable -Name ConfOnboardingRuntime -Value @{
    AuthTrimmed             = $null
    AccountsResult          = 0
    Header                  = $null
    LoginSplat              = @{}
    ExcludedGroupPatterns   = @($ConfUserInformationExcludedGroupPatterns)
    ConfAccountCredFile     = $null
    ConnectionTimeoutSeconds = 300
    PVWALogonUrl            = $null
    PVWAGetSafesUrl         = $null
    PVWAGetUsersUrl         = $null
    PVWAAccountsUrl         = $null
    ConfDirLogs             = $null
    ConfPVWAURL             = $null
    isAutosys               = $false
    PVWAAuthBody            = $null
}

# Export variables and functions
Export-ModuleMember -Variable Environment, ConfRUNUSER, ConfLogFile, ConfDirFiles, ConfDirLogs, ConfDirRepGen, ConfPlatfrmLogs, ConfIACOnbdLogs
Export-ModuleMember -Variable ConfUsersLogs, ConfADLogs, ConfVaultFile, ConfEnvFile, ConfUserAccount, ConfAccountCredFile
Export-ModuleMember -Variable ConfUserUsers, ConfUserCredFile, ConfUsersSafes, ConfSafesCredFile, ConfSUPPORTENV
Export-ModuleMember -Variable ConfPVWAURL, ConfDestDrive, ConfVaultName, ConfVaultAddr
Export-ModuleMember -Variable ConfADDomains, ConfADGroups, ConfADAccessGrp, ADDomainList
Export-ModuleMember -Variable ConfLegacyConfigurationModulePath, ConfADConfigurationModuleName, ConfSafeScanLogPath
Export-ModuleMember -Variable ConfPVWAEndpointSuffixes, ConfUserInformationExcludedGroupPatterns
Export-ModuleMember -Variable ConfUserGroupAssignmentConfig, ConfHumanUserScanConfig, ConfOnboardingRuntime
