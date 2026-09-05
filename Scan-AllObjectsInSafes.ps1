<#
.SYNOPSIS
    Runfile for CyberArk Account Reporting - report on objects, users and safes.

.DESCRIPTION
    This script connects to the CyberArk PVWA (Password Vault Web Access) API to generate
    comprehensive reports on accounts, users and safes stored in the CyberArk vault.

    REPORTING OPTIONS:
    - Accounts Report: All password objects with their properties and management status
    - Users Report: All vault users with permissions and group memberships
    - Safes Report: All safes with retention policies and creation details

.NOTES
    Basic Configuration Options
    - ConfPVWAURL: PVWA base URL supplied by the configured configuration module
    - ConnectionTimeoutSeconds: HTTP request timeout in seconds (default: 300)

.EXAMPLE
    Basic usage with retry defaults
    .\Scan-AllObjectsInSafes.ps1 -ReportAccounts

    Custom connection timeout for an unstable network
    .\Scan-AllObjectsInSafes.ps1 -ReportAccounts -ConnectionTimeoutSeconds 600

    Generate all reports
    .\Scan-AllObjectsInSafes.ps1 -ReportAccounts -ReportUsers -ReportSafes
#>

[CmdletBinding()]
param (
    [switch]$ReportAccounts,                               # Generate accounts report (password objects)
    [switch]$ReportUsers,                                  # Generate users report (vault users)
    [switch]$ReportSafes,                                  # Generate safes report (safe details)
    [int]$ConnectionTimeoutSeconds = 300                   # HTTP request timeout (5 minutes default)
)

# Force TLS 1.2 and avoid small-request delays in Windows PowerShell 5.1.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::Expect100Continue = $false
[Net.ServicePointManager]::UseNagleAlgorithm = $false
# Keep revocation behaviour unchanged until the PVWA certificate policy is confirmed.
[Net.ServicePointManager]::CheckCertificateRevocationList = $false

# Initialize exit code (0 = success, 1 = failure)
$exitCode = 0

$functionsModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Config/PSFunctions.psm1'

# Load shared functions first because they expose the legacy configuration path.
try {
    Import-Module -Name $functionsModulePath -Force -ErrorAction Stop
    Import-Module -Name $CybLegacyConfigurationModulePath -Force -Global -ErrorAction Stop
} catch {
    Write-Output "ERROR: Unable to import modules: $($_.Exception.Message)"
    exit 1
}

# Set script preferences based on command-line parameters
$InDebug = $PSBoundParameters.Debug.IsPresent
$InVerbose = $PSBoundParameters.Verbose.IsPresent
# Autosys runs suppress interactive progress while retaining log output.
$isAutosys = [bool][Environment]::GetEnvironmentVariable('AUTO_JOB_NAME')

# Configure global preferences
Set-GlobalPreferences -EnableVerbose:$InVerbose -EnableDebug:$InDebug -IsAutosys:$isAutosys

# Stop before API work when environment-specific configuration is missing.
if ([string]::IsNullOrWhiteSpace([string]$Environment)) {
    LogError "Environment variable must be set via $CybLegacyConfigurationModulePath"
    exit 1
}

# Initialize logging system
$Script:LogPath = $CybSafeScanLogPath
LogStartScript

# Resolve legacy relative paths from the configured files directory.
Set-Location $ConfDirFiles

# Build CyberArk API endpoint URLs from shared configuration.
if ([string]::IsNullOrWhiteSpace([string]$ConfPVWAURL)) {
    LogError "ConfPVWAURL must be set via $CybLegacyConfigurationModulePath"
    exit 1
}

# Normalize once so endpoint joins do not produce double slashes.
$PVWABaseUrl     = $ConfPVWAURL.TrimEnd('/')
$PVWALogonUrl    = "$PVWABaseUrl/$($CybPVWAEndpointSuffixes.Authentication)"
$PVWAAccountsUrl = "$PVWABaseUrl/$($CybPVWAEndpointSuffixes.Accounts)"
$PVWAGetUsersUrl = "$PVWABaseUrl/$($CybPVWAEndpointSuffixes.Users)"
$PVWAGetSafesUrl = "$PVWABaseUrl/$($CybPVWAEndpointSuffixes.Safes)"

# Pass only runtime values needed by the shared function module.
Initialize-CybOnboardingContext -Configuration @{
    ConfAccountCredFile      = $ConfAccountCredFile
    ConnectionTimeoutSeconds = $ConnectionTimeoutSeconds
    PVWALogonUrl             = $PVWALogonUrl
    PVWAGetSafesUrl          = $PVWAGetSafesUrl
    PVWAGetUsersUrl          = $PVWAGetUsersUrl
    PVWAAccountsUrl          = $PVWAAccountsUrl
    ConfDirLogs              = $ConfDirLogs
    ConfPVWAURL              = $PVWABaseUrl
    isAutosys                = $isAutosys
}

# Log URLs if debug mode is enabled
if ($InDebug) {
    LogDebug "PVWALogonUrl = $PVWALogonUrl"
    LogDebug "PVWAAccountsUrl = $PVWAAccountsUrl"
    LogDebug "PVWAGetUsersUrl = $PVWAGetUsersUrl"
    LogDebug "PVWAGetSafesUrl = $PVWAGetSafesUrl"
}

# Reuse one token for all reports; requests refresh it only after a 401.
try {
    LogOutput "Authenticating with PVWA..."
    $null = Get-AuthToken
    LogOutput "Authentication successful"
} catch {
    LogError "Authentication failed: $($_.Exception.Message)"
    exit 1
}

# Generate requested reports
# Each report runs independently - failures are logged but don't stop other reports

# Generate Accounts Report if requested
if ($ReportAccounts) {
    try {
        Process-AccountsReport
    } catch {
        LogError "Accounts report failed: $($_.Exception.Message)"
        $exitCode = 1
    }
}

# Generate Users Report if requested
if ($ReportUsers) {
    try {
        Process-UsersReport
    } catch {
        LogError "Users report failed: $($_.Exception.Message)"
        $exitCode = 1
    }
}

# Generate Safes Report if requested
if ($ReportSafes) {
    try {
        Process-SafesReport
    } catch {
        LogError "Safes report failed: $($_.Exception.Message)"
        $exitCode = 1
    }
}

# Perform cleanup operations and exit
Cleanup
LogOutput "Script execution completed with exit code: $exitCode"
exit $exitCode
