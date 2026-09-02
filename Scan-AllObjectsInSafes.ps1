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
    - MaxRetries: Number of retry attempts for failed API calls (default: 3)
    - RetryDelaySeconds: Initial delay between retries in seconds (default: 5)
    - ConnectionTimeoutSeconds: HTTP request timeout in seconds (default: 300)

.EXAMPLE
    Basic usage with retry defaults
    -PVWAUrl "https://PVWAURL.fqdn.nom" -ReportAccounts

    Custom retry settings for unstable networks
    -PVWAUrl "https://PVWAURL.fqdn.nom" -ReportAccounts -MaxRetries 5 -RetryDelaySeconds 10 -ConnectionTimeoutSeconds 600

    All reports with custom page size
    -PVWAUrl "https://PVWAURL.fqdn.nom" -ReportAccounts -ReportUsers -ReportSafes -AccountsPageSize 50
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$PVWAUrl,        # CyberArk PVWA base URL (e.g., https://pvwa.company.com)
    [switch]$ReportAccounts,                               # Generate accounts report (password objects)
    [switch]$ReportUsers,                                  # Generate users report (vault users)
    [switch]$ReportSafes,                                  # Generate safes report (safe details)
    [int]$AccountsPageSize = 100,                          # Number of accounts to retrieve per API call
    [int]$MaxRetries = 3,                                  # Maximum retry attempts for failed API calls
    [int]$RetryDelaySeconds = 5,                           # Initial delay between retries (uses exponential backoff)
    [int]$ConnectionTimeoutSeconds = 300                   # HTTP request timeout (5 minutes default)
)

# Main script body.

# Configure .NET HTTP stack for high-volume parallel API requests
# These settings prevent connection pool exhaustion and stale connection reuse
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::Expect100Continue = $false
[Net.ServicePointManager]::DefaultConnectionLimit = 10
[Net.ServicePointManager]::UseNagleAlgorithm = $false
[Net.ServicePointManager]::CheckCertificateRevocationList = $false

# Initialize exit code (0 = success, 1 = failure)
$exitCode = 0

$functionsModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Config/PSFunctions.psm1'

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
$isAutosys = [bool][Environment]::GetEnvironmentVariable('AUTO_JOB_NAME')

# Configure global preferences
Set-GlobalPreferences -EnableVerbose:$InVerbose -EnableDebug:$InDebug -IsAutosys:$isAutosys

# Validate environment is configured
if (-not $Environment -and $null -eq $Environment) {
    LogError "Environment variable must be set via $CybLegacyConfigurationModulePath"
    exit 1
}

# Initialize logging system
$Script:LogPath = $CybSafeScanLogPath
LogStartScript

# Set working directory for script execution
Set-Location $ConfDirFiles

# Build CyberArk API endpoint URLs from shared configuration.
$PVWALogonUrl = $ConfPVWAURL + $CybPVWAEndpointSuffixes.Authentication
$PVWAAccountsUrl = $ConfPVWAURL + $CybPVWAEndpointSuffixes.Accounts
$PVWAGetUsersUrl = $ConfPVWAURL + $CybPVWAEndpointSuffixes.Users
$PVWAGetSafesUrl = $ConfPVWAURL + $CybPVWAEndpointSuffixes.Safes

Initialize-CybOnboardingContext -Configuration @{
    ConfAccountCredFile      = $ConfAccountCredFile
    ConnectionTimeoutSeconds = $ConnectionTimeoutSeconds
    PVWALogonUrl             = $PVWALogonUrl
    PVWAGetSafesUrl          = $PVWAGetSafesUrl
    PVWAGetUsersUrl          = $PVWAGetUsersUrl
    PVWAAccountsUrl          = $PVWAAccountsUrl
    ConfDirLogs              = $ConfDirLogs
    ConfPVWAURL              = $ConfPVWAURL
    isAutosys                = $isAutosys
}

# Log URLs if debug mode is enabled
if ($InDebug) {
    LogDebug "PVWALogonUrl = $PVWALogonUrl"
    LogDebug "PVWAAccountsUrl = $PVWAAccountsUrl"
    LogDebug "PVWAGetUsersUrl = $PVWAGetUsersUrl"
    LogDebug "PVWAGetSafesUrl = $PVWAGetSafesUrl"
}

# Create temporary file for detailed error logging
$RandomFile = [System.IO.Path]::GetRandomFileName()
$ErrFile = "C:\TEMP\${RandomFile}.out"

# Authenticate with CyberArk PVWA
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
