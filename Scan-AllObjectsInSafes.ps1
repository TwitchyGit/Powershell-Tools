# PowerShell7 update: Run this entry point with the approved PowerShell 7.6 Core executable.
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

# PowerShell7 update: Convert any uncaught failure into an AutoSys-safe message and exit code.
trap {
    Write-Output "ERROR: Unhandled account-reporting failure: $($_.Exception.Message)"
    exit 1
}
$ErrorActionPreference = 'Stop'

# Initialize exit code (0 = success, 1 = failure)
$exitCode = 0

$configModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Config/ConfigModule.psm1'

# Load shared configuration before the reporting functions.
try {
    Import-Module -Name $configModulePath -Force -ErrorAction Stop
} catch {
    Write-Output "ERROR: Unable to import configuration: $($_.Exception.Message)"
    exit 1
}

# PowerShell7 update: HttpClient handles TLS and OS certificate trust without ServicePointManager overrides.

$functionsModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Config/PSFunctions.psm1'

# Load the PowerShell 7 reporting functions and legacy environment configuration.
try {
    Import-Module -Name $functionsModulePath -Force -ErrorAction Stop
    Import-Module -Name $ConfLegacyConfigurationModulePath -Force -Global -ErrorAction Stop
} catch {
    # Log* functions may not be loaded yet if the import above failed, so fall back to Write-Output.
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

# PowerShell7 update: AutoSys must fail clearly when no report action was selected.
if (-not ($ReportAccounts -or $ReportUsers -or $ReportSafes)) {
    LogError 'At least one report switch is required.'
    exit 1
}

# Stop before API work when environment-specific configuration is missing.
if ([string]::IsNullOrWhiteSpace([string]$Environment)) {
    LogError "Environment variable must be set via $ConfLegacyConfigurationModulePath"
    exit 1
}

# Initialize logging system
$Script:LogPath = $ConfSafeScanLogPath
$runLock = $null
try {
    # PowerShell7 update: Prevent simultaneous writers from corrupting the fixed report and log files.
    $runLock = Enter-CybOnboardingRunLock -LockPath "$ConfSafeScanLogPath.lock"
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
    exit 1
}
LogStartScript

# Resolve legacy relative paths from the configured files directory.
Set-Location $ConfDirFiles

# Build CyberArk API endpoint URLs from shared configuration.
if ([string]::IsNullOrWhiteSpace([string]$ConfPVWAURL)) {
    LogError "ConfPVWAURL must be set via $ConfLegacyConfigurationModulePath"
    exit 1
}

# Normalize once so endpoint joins do not produce double slashes.
$PVWABaseUrl     = $ConfPVWAURL.TrimEnd('/')
$PVWALogonUrl    = "$PVWABaseUrl/$($ConfPVWAEndpointSuffixes.Authentication)"
$PVWALogoffUrl   = "$PVWABaseUrl/$($ConfPVWAEndpointSuffixes.Logoff)"
$PVWAAccountsUrl = "$PVWABaseUrl/$($ConfPVWAEndpointSuffixes.Accounts)"
$PVWAGetUsersUrl = "$PVWABaseUrl/$($ConfPVWAEndpointSuffixes.Users)"
$PVWAGetSafesUrl = "$PVWABaseUrl/$($ConfPVWAEndpointSuffixes.Safes)"

# Pass only runtime values needed by the shared function module.
Initialize-CybOnboardingContext -Configuration @{
    ConfAccountCredFile      = $ConfAccountCredFile
    ConnectionTimeoutSeconds = $ConnectionTimeoutSeconds
    PVWALogonUrl             = $PVWALogonUrl
    PVWALogoffUrl            = $PVWALogoffUrl
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

# PowerShell7 update: Hold the process lock through final logging before AutoSys receives the exit code.
try {
    Cleanup
    LogOutput "Script execution completed with exit code: $exitCode"
} finally {
    Exit-CybOnboardingRunLock -LockHandle $runLock
}
exit $exitCode
