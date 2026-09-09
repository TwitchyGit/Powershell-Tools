# PowerShell7 update: Shared functions use PowerShell 7.6 HTTP and encoding behaviour.
<#
.SYNOPSIS
    Provides shared Active Directory and CyberArk onboarding functions.
.DESCRIPTION
    Imports the onboarding configuration module and exposes reusable helpers for
    Active Directory lookup, PVWA authentication, safe and account retrieval,
    user reporting, logging, cleanup and onboarding runtime initialization.
#>

$configurationModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'ConfigModule.psm1'

if (-not (Test-Path -LiteralPath $configurationModulePath -PathType Leaf)) {
    Write-Output "ERROR: Configuration module not found: $configurationModulePath"
    exit 1
}

# Import locally so mutable runtime state stays scoped to this function module.
# PowerShell7 update: Reuse the caller's configuration module instance and its runtime state.
Import-Module -Name $configurationModulePath -Scope Local -ErrorAction Stop

# Logging and preference helpers used across the onboarding scripts.

# Applies -Verbose/-Debug switches and Autosys-safe stream preferences globally,
# so every script configures logging the same way instead of repeating this per-caller.
$script:InDebug = $false
function Set-GlobalPreferences {
    [CmdletBinding()]
    param(
        [switch]$EnableVerbose,
        [switch]$EnableDebug,
        [switch]$IsAutosys
    )

    if ($EnableDebug) {
        $Global:DebugPreference = 'Continue'
        $script:InDebug = $true
        Write-Information "DEBUG: Debug mode enabled globally" -InformationAction Continue
    } else {
        $Global:DebugPreference = 'SilentlyContinue'
    }

    if ($EnableVerbose) {
        $Global:VerbosePreference = 'Continue'
        Write-Information "VERBOSE: Verbose mode enabled globally" -InformationAction Continue
    } else {
        $Global:VerbosePreference = 'SilentlyContinue'
    }

    # PowerShell7 update: AutoSys has no console, so use process-wide noninteractive preferences.
    $Global:ConfirmPreference = 'None'
    if ($IsAutosys) {
        Write-Information "AutoSys detected: $IsAutosys" -InformationAction Continue
        $Global:WarningPreference     = 'SilentlyContinue'
        $Global:InformationPreference = 'SilentlyContinue'
        $Global:VerbosePreference     = 'SilentlyContinue'
        $Global:DebugPreference       = 'SilentlyContinue'
        $Global:ProgressPreference    = 'SilentlyContinue'
    }
}

# Writes the log file's start-of-run header (called once at script startup).
function LogStartScript {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    # PowerShell7 update: Use the information stream so log text cannot contaminate returned API data.
    Write-Information ("=" * 80) -InformationAction Continue
    Write-Information "INFO: Script started at $timestamp" -InformationAction Continue

    Write-Debug "ReportName: $ReportName `nScriptInfo: $ScriptInfo `nsetReportDir: $setReportDir `nConfDirLogs:  " +
        "$ConfDirLogs `nConfLogFile: $ConfLogFile `nConfFileDirs:  $ConfDirFiles"

    if ($ConfLogFile) {
        Write-Information "INFO: Logfile written to $ConfLogFile" -InformationAction Continue
        Add-Content -Path $ConfLogFile -Value ("=" * 80) -ErrorAction SilentlyContinue
        Add-Content -Path $ConfLogFile -Value "Script started at $timestamp" -ErrorAction SilentlyContinue
    } else {
        Write-Information "ERROR: Unable to write to logfile ($ConfLogFile)" -InformationAction Continue
    }
}

# Writes an INFO-prefixed line to stdout and $ConfLogFile. An empty message (or one
# starting with `n) prints a blank line instead; a message containing "====" prints
# a full-width separator instead - neither of those gets the INFO prefix or file log.
function LogOutput {
    param(
        [string]$Message
    )

    $check = $false
    if ($Message -eq "" -or $Message.StartsWith("`n")) {
        # PowerShell7 update: Keep operational logging off the success stream.
        Write-Information "" -InformationAction Continue; $check = $true
    }
    if ($Message -like "*====*") {
        Write-Information ("=" * 80) -InformationAction Continue; $check = $true
    }
    if ($check -eq $false) {
        Write-Information "INFO: $Message" -InformationAction Continue
        if ($ConfLogFile) {
            Add-Content -Path $ConfLogFile -Value "INFO: $Message" -ErrorAction SilentlyContinue
        }
    }
}

# Writes an ERROR-prefixed line to stdout and $ConfLogFile.
function LogError {
    param(
        [string]$Message
    )

    # PowerShell7 update: Keep errors visible to AutoSys without mixing them into returned objects.
    Write-Information "ERROR: $Message" -InformationAction Continue
    if ($ConfLogFile) {
        Add-Content -Path $ConfLogFile -Value "ERROR: $Message" -ErrorAction SilentlyContinue
    }
}

# Writes a WARN-prefixed line to stdout and $ConfLogFile, and tracks how many
# warnings have been logged in $Global:LogWarnCount.
function LogWarn {
    param(
        [string]$Message
    )

    if (-not (Test-Path Variable:Global:LogWarnCount)) { $Global:LogWarnCount = 0 }
    $Global:LogWarnCount++

    # PowerShell7 update: Use a redirectable non-success stream because AutoSys has no console object.
    Write-Information "WARN: $Message" -InformationAction Continue
    if ($ConfLogFile) {
        Add-Content -Path $ConfLogFile -Value "WARN: $Message" -ErrorAction SilentlyContinue
    }
}

# Writes a DEBUG-prefixed line to stdout and $ConfLogFile, only when debug mode is on
# (set via Set-GlobalPreferences -EnableDebug).
function LogDebug {
    param(
        [string]$Message
    )

    if ($script:InDebug) {
        # PowerShell7 update: Write to a redirectable non-success stream for unattended execution.
        Write-Information "DEBUG: $Message" -InformationAction Continue
        if ($ConfLogFile) {
            Add-Content -Path $ConfLogFile -Value "DEBUG: $Message" -ErrorAction SilentlyContinue
        }
    }
}

# Converts a PVWA epoch timestamp (seconds, or microseconds for values over 10 digits)
# to a formatted date plus an age bucket (Recent / OlderThanSixMonths / OlderThanTwelveMonths).
function ConvertDate($epochdate) {
    if (($epochdate).length -gt 10 ) {
        $seconds = $epochdate / 1000000
        $dateTime = [DateTimeOffset]::FromUnixTimeSeconds($seconds)
        $result = $dateTime.ToString("dd/MM/yyyy HH:mm")
    } else {
        $dateTime = [DateTimeOffset]::FromUnixTimeSeconds($epochdate)
        $result = $dateTime.ToString("dd/MM/yyyy HH:mm")
    }

    # Check ages thresholds
    $sixMonthsAgo = (Get-Date).AddMonths(-6)
    $twelveMonthsAgo = (Get-Date).AddMonths(-12)

    if ($datetime.DateTime -lt $twelveMonthsAgo) {
        $ageCategory = "OlderThanSixMonths"
    } elseif ($datetime.DateTime -lt $sixMonthsAgo) {
        $ageCategory = "OlderThanTwelveMonths"
    } else {
        $ageCategory = "Recent"
    }

    return @{
        Date                    = $result
        AgeCategory             = $ageCategory
        IsOlderThanSixMonths    = $datetime.DateTime -lt $sixMonthsAgo
        IsOlderThanTwelveMonths = $datetime.DateTime -lt $twelveMonthsAgo
    }
}

# Merges caller-supplied values into $ConfOnboardingRuntime (only known keys accepted),
# so scripts can seed per-run state like credentials and PVWA URLs before calling into
# the rest of this module.
function Initialize-CybOnboardingContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration
    )

    # Reject unknown keys so configuration errors fail before any API request.
    foreach ($entry in $Configuration.GetEnumerator()) {
        if (-not $ConfOnboardingRuntime.ContainsKey($entry.Key)) {
            Write-Error "Unsupported onboarding context value: $($entry.Key)" -ErrorAction Stop
        }

        $ConfOnboardingRuntime[$entry.Key] = $entry.Value
    }
}

# Active Directory helpers.

# Escapes LDAP filter metacharacters (\, *, (, ), NUL) so a group name containing
# them can't break out of the filter string built in Resolve-GroupDN.
function Escape-LDAPFilter {
  param([string]$Value)
  $Value = $Value -replace '\\', '\5c'
  $Value = $Value -replace '\*', '\2a'
  $Value = $Value -replace '\(', '\28'
  $Value = $Value -replace '\)', '\29'
  $Value = $Value -replace '\x00', '\00'
  return $Value
}

# Resolves a group name to its distinguishedName in one domain, trying a direct
# identity lookup first and falling back to a samAccountName/CN search. Returns
# $null rather than a terminating error when the group cannot be found, so callers can skip it.
function Resolve-GroupDN {
  param([string]$Group,[string]$Domain,[System.Management.Automation.PSCredential]$Cred)
  $common = @{ Server = $Domain }
  if ($Cred) { $common.Credential = $Cred }

  # Direct lookup avoids a broader directory search when the name resolves.
  try {
    $g = Get-ADGroup @common -Identity $Group -Properties distinguishedName
    if ($g -and $g.DistinguishedName) { return $g.DistinguishedName }
  } catch { }

  # Search by account name or CN because callers may supply either form.
  try {
    $base = (Get-ADDomain @common).DistinguishedName
    $escaped = Escape-LDAPFilter -Value $Group
    $flt = "(|(samAccountName=$escaped)(cn=$escaped))"
    $g2 = Get-ADGroup @common -LDAPFilter $flt -SearchBase $base -SearchScope Subtree -Properties distinguishedName |
          Select-Object -First 1
    if ($g2 -and $g2.DistinguishedName) { return $g2.DistinguishedName }
  } catch { }

  return $null
}

# CyberArk safe and account reporting functions.

<#
.SYNOPSIS
    Shared transient/permanent error classification for PVWA REST calls, used
    by Invoke-PVWARestMethod so every caller (Get-AllSafes, Get-Users,
    Get-AllAccounts) retries on the same policy instead of each reimplementing
    its own judgment call.

.NOTES
    A connection-refused/could-not-connect failure (e.g. the vault itself is
    down) surfaces as a WebException with no status code and a message
    matching one of the connection patterns below, so it is treated as
    transient like a timeout - worth retrying, since the vault may come back
    within the retry window.
#>
$script:PVWATransientPatterns = @(
    'timeout', 'timed out',
    'unable to connect', 'no connection could be made',
    'connection.*(closed|reset|refused)', 'actively refused',
    'could not be resolved', 'the underlying connection was closed',
    'a task was canceled'
)

$script:PVWAPermanentPatterns = @(
    'not authorized', '\b403\b',
    'not found', '\b404\b',
    'validation', '\b400\b'
)

$script:PVWAMaxAttempts = 3
$script:PVWARetryDelaySeconds = 10
$script:SafeListingFailedPageCount = 0
$script:LastPVWAResponseMetadata = $null

# PowerShell7 update: Walk the complete exception chain because HttpClient wraps transport failures.
function Get-PVWAExceptionDetail {
    param([Parameter(Mandatory)][System.Exception]$Exception)

    $details = [System.Collections.Generic.List[string]]::new()
    $current = $Exception
    while ($null -ne $current) {
        [void]$details.Add("$($current.GetType().FullName): $($current.Message)")
        $current = $current.InnerException
    }
    return $details -join ' -> '
}

# PowerShell7 update: Identify the specific transport error eligible for one login-and-retry recovery.
function Test-PVWAConnectionClosedError {
    param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord)

    $detail = Get-PVWAExceptionDetail -Exception $ErrorRecord.Exception
    return $detail -match 'underlying connection was closed|unexpected error occurred on a send|connection.*(closed|reset)|response ended prematurely'
}

# PowerShell7 update: Report response shape without exposing valid account JSON or session tokens.
function Get-PVWAResponseDiagnostic {
    param([AllowNull()][string]$Content)

    $metadata = if ($script:LastPVWAResponseMetadata) {
        "Status=$($script:LastPVWAResponseMetadata.StatusCode); ContentType=$($script:LastPVWAResponseMetadata.ContentType); ContentLength=$($script:LastPVWAResponseMetadata.ContentLength); Protocol=$($script:LastPVWAResponseMetadata.ProtocolVersion)"
    } else {
        'Response metadata unavailable'
    }

    if ([string]::IsNullOrWhiteSpace($Content)) { return "$metadata; Body=empty" }
    if ($script:LastPVWAResponseMetadata.ContentType -match 'json') {
        return "$metadata; Body=JSON body suppressed"
    }
    $trimmed = $Content.TrimStart()
    if ($trimmed.StartsWith('{') -or $trimmed.StartsWith('[')) {
        return "$metadata; Body=JSON-like body suppressed"
    }

    $preview = ($trimmed -replace '[\r\n\t]+', ' ')
    $preview = $preview.Substring(0, [Math]::Min(160, $preview.Length))
    $preview = $preview -replace '(?i)(authorization|password|token)\s*[:=]\s*\S+', '$1=[redacted]'
    return "$metadata; NonJsonPreview=$preview"
}

function Test-PVWATransientError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord]$ErrorRecord,

        [Parameter(Mandatory = $false)]
        [Nullable[int]]$StatusCode = $null
    )

    if ($StatusCode -in @(400, 403, 404)) { return $false }

    # Treat 401 as transient because it normally means the shared token expired.
    if ($StatusCode -in @(401, 429, 500, 502, 503, 504)) { return $true }

    $msg = Get-PVWAExceptionDetail -Exception $ErrorRecord.Exception

    foreach ($pattern in $script:PVWAPermanentPatterns) {
        if ($msg -match $pattern) { return $false }
    }
    foreach ($pattern in $script:PVWATransientPatterns) {
        if ($msg -match $pattern) { return $true }
    }

    if ($ErrorRecord.Exception.GetType().FullName -match 'WebException|HttpRequestException|SocketException|TaskCanceledException|IOException') {
        return $true
    }

    # An error shape we don't recognize defaults to not transient, so a call
    # fails fast instead of retrying something it cannot classify.
    return $false
}

# Resolves a PVWA pagination "nextLink" (absolute or relative) to a full URL on the
# same PVWA host, rejecting any link that points elsewhere or uses an unsupported scheme.
function Resolve-PVWANextLink {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$NextLink
    )

    $baseUri = [Uri]::new($BaseUrl.TrimEnd('/') + '/')
    if ($NextLink -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
        [Uri]$absoluteUri = $null
        if (-not [Uri]::TryCreate($NextLink, [UriKind]::Absolute, [ref]$absoluteUri)) {
            Write-Error "PVWA nextLink is not a valid absolute URI: $NextLink" -ErrorAction Stop
        }
        if ($absoluteUri.Scheme -notin @('http', 'https')) {
            Write-Error "PVWA nextLink uses an unsupported URI scheme: $NextLink" -ErrorAction Stop
        }
        if (-not $absoluteUri.Scheme.Equals($baseUri.Scheme, [StringComparison]::OrdinalIgnoreCase) -or
            -not $absoluteUri.Authority.Equals($baseUri.Authority, [StringComparison]::OrdinalIgnoreCase)) {
            Write-Error "PVWA nextLink points outside the configured PVWA host: $NextLink" -ErrorAction Stop
        }
        return $absoluteUri.AbsoluteUri
    }

    $relativeLink = $NextLink.TrimStart('/')
    $basePath = $baseUri.AbsolutePath.Trim('/')

    # Resolve paths containing PasswordVault from the host root to avoid duplication.
    if (-not [string]::IsNullOrWhiteSpace($basePath)) {
        $basePathPrefix = $basePath + '/'
        if ($relativeLink.Equals($basePath, [StringComparison]::OrdinalIgnoreCase) -or
            $relativeLink.StartsWith($basePathPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            $hostRoot = [Uri]::new("$($baseUri.Scheme)://$($baseUri.Authority)/")
            return [Uri]::new($hostRoot, $relativeLink).AbsoluteUri
        }
    }

    return [Uri]::new($baseUri, $relativeLink).AbsoluteUri
}

<#
.SYNOPSIS
    Calls the PVWA REST API with retry on transient failures only (see
    Test-PVWATransientError). Returns the response content on success.
    Throws on a non-retryable error or once retries are exhausted, so a
    caller can tell "call failed" apart from "call succeeded with an empty
    body" using a normal try/catch, instead of both cases returning $null.
#>
function Invoke-PVWARestMethod {
    [CmdletBinding()]
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body = $null,
        [int]$TimeoutSec = 300,
        [ValidateRange(1, 10)]
        [int]$MaxAttempts = $script:PVWAMaxAttempts,
        [switch]$ReauthenticateOnConnectionClosed
    )

    $attempt = 0
    $lastError = $null
    $connectionRecoveryUsed = $false

    if (-not $Headers.ContainsKey('Accept')) { $Headers['Accept'] = 'application/json' }

    while ($attempt -lt $MaxAttempts) {
        $attempt++
        $script:LastPVWAResponseMetadata = $null

        try {
            LogDebug "Attempt $attempt of $MaxAttempts for: $Uri"

            # PowerShell7 update: Request HTTP/2 with separate connection and operation timeouts.
            $requestParams = @{
                Uri                      = $Uri
                Method                   = $Method
                Headers                  = $Headers
                ContentType              = 'application/json'
                HttpVersion              = [Version]'2.0'
                ConnectionTimeoutSeconds = $TimeoutSec
                OperationTimeoutSeconds  = $TimeoutSec
                ErrorAction              = 'Stop'
            }

            if ($Body) { $requestParams.Body = $Body }

            $response = Invoke-WebRequest @requestParams
            $script:LastPVWAResponseMetadata = [PSCustomObject]@{
                StatusCode      = $response.StatusCode
                ContentType     = $response.Headers['Content-Type']
                ContentLength   = $response.Headers['Content-Length']
                ProtocolVersion = $response.BaseResponse.Version
            }
            return $response.Content

        } catch {
            $lastError = $_
            $statusCode = $null

            if ($_.Exception.Response) {
                try {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                } catch {
                    # Status code not available
                }
                try {
                    # PowerShell7 update: Capture failed-response headers without reading sensitive bodies.
                    $script:LastPVWAResponseMetadata = [PSCustomObject]@{
                        StatusCode      = $statusCode
                        ContentType     = $_.Exception.Response.Content.Headers.ContentType
                        ContentLength   = $_.Exception.Response.Content.Headers.ContentLength
                        ProtocolVersion = $_.Exception.Response.Version
                    }
                } catch { }
            }

            if ($null -eq $statusCode -and $null -ne $_.Exception.StatusCode) {
                try { $statusCode = [int]$_.Exception.StatusCode } catch { }
            }

            $exceptionDetail = Get-PVWAExceptionDetail -Exception $_.Exception
            LogError "Attempt $attempt failed for $Uri - Status: $statusCode; Error: $exceptionDetail"

            $isTransient = Test-PVWATransientError -ErrorRecord $_ -StatusCode $statusCode

            if (-not $isTransient) {
                $failure = [System.Exception]::new(
                    "Non-retryable error calling ${Uri}: $exceptionDetail",
                    $_.Exception
                )
                $failure.Data['PVWATransient'] = $false
                Write-Error -Exception $failure -ErrorAction Stop
            }

            # PowerShell7 update: On the first connection-closed error, prove PVWA login and retry this request once.
            if ($ReauthenticateOnConnectionClosed -and -not $connectionRecoveryUsed -and
                $Headers.ContainsKey('Authorization') -and (Test-PVWAConnectionClosedError -ErrorRecord $_)) {
                $connectionRecoveryUsed = $true
                LogWarn "Connection closed while calling PVWA. Performing one fresh login before retrying the current request."
                try {
                    $ConfOnboardingRuntime.AuthTrimmed = Get-AuthToken -SingleAttempt
                    $Headers['Authorization'] = $ConfOnboardingRuntime.AuthTrimmed
                    $attempt--
                    continue
                } catch {
                    $failure = [System.Exception]::new(
                        "Connection recovery login failed calling ${Uri}: $($_.Exception.Message)",
                        $_.Exception
                    )
                    $failure.Data['PVWATransient'] = $true
                    Write-Error -Exception $failure -ErrorAction Stop
                }
            }

            if ($attempt -ge $MaxAttempts) { break }

            # Re-authenticate on 401 before the next attempt - the retry still
            # counts against the fixed attempt limit like any other transient failure.
            if ($statusCode -eq 401 -and $Headers.ContainsKey('Authorization')) {
                LogOutput "Re-authenticating..."
                try {
                    $ConfOnboardingRuntime.AuthTrimmed = Get-AuthToken
                    $Headers['Authorization'] = $ConfOnboardingRuntime.AuthTrimmed
                } catch {
                    $failure = [System.Exception]::new(
                        "Re-authentication failed calling ${Uri}: $($_.Exception.Message)",
                        $_.Exception
                    )
                    $failure.Data['PVWATransient'] = $true
                    Write-Error -Exception $failure -ErrorAction Stop
                }
            }

            $waitTime = $script:PVWARetryDelaySeconds * [Math]::Pow(2, $attempt - 1)
            LogOutput "Retrying in $waitTime seconds..."
            Start-Sleep -Seconds $waitTime
        }
    }

    $failure = [System.Exception]::new(
        "Failed calling $Uri after $attempt attempt(s): $($lastError.Exception.Message)",
        $lastError.Exception
    )
    $failure.Data['PVWATransient'] = $true
    Write-Error -Exception $failure -ErrorAction Stop
}

# Logs on to PVWA using the credential file in $ConfOnboardingRuntime.ConfAccountCredFile
# and returns the session token, also caching it on $ConfOnboardingRuntime.AuthTrimmed.
function Get-AuthToken {
    [CmdletBinding()]
    param(
        [switch]$SingleAttempt
    )

    if (-not (Test-Path $ConfOnboardingRuntime.ConfAccountCredFile)) {
        Write-Error "Credential file not found: $($ConfOnboardingRuntime.ConfAccountCredFile)" -ErrorAction Stop
    }

    try {
        $PVWACreds = Import-Clixml -Path $ConfOnboardingRuntime.ConfAccountCredFile
        
        if (-not $PVWACreds -or -not $PVWACreds.UserName -or -not $PVWACreds.Password) {
            Write-Error "Invalid credentials in file" -ErrorAction Stop
        }

        $AuthBody = @{
            username          = $PVWACreds.UserName
            password          = $PVWACreds.GetNetworkCredential().Password
            # PowerShell7 update: Allow independent scheduled processes to hold separate PVWA sessions.
            concurrentSession = $true
        } | ConvertTo-Json

        LogDebug "Authenticating as: $($PVWACreds.UserName)"

        $authMaxAttempts = if ($SingleAttempt) { 1 } else { $script:PVWAMaxAttempts }

        $authResponse = Invoke-PVWARestMethod `
            -Uri $ConfOnboardingRuntime.PVWALogonUrl `
            -Method "POST" `
            -Body $AuthBody `
            -TimeoutSec $ConfOnboardingRuntime.ConnectionTimeoutSeconds `
            -MaxAttempts $authMaxAttempts

        if (-not $authResponse) {
            Write-Error "Authentication failed - no token received" -ErrorAction Stop
        }

        $token = $authResponse -replace '"', ''
        $ConfOnboardingRuntime.AuthTrimmed = $token
        LogDebug "Authentication successful"
        return $token

    } catch {
        $authenticationFailure = [System.Exception]::new("Authentication failed: $($_.Exception.Message)", $_.Exception)
        Write-Error -Exception $authenticationFailure -ErrorAction Stop
    } finally {
        if ($PVWACreds) {
            $PVWACreds.Password.Dispose()
        }
    }
}

# Pages through the PVWA Safes API and returns every Safe. Stops early after three
# consecutive page failures rather than retrying an unhealthy vault indefinitely.
function Get-AllSafes {
    [CmdletBinding()]
    param()

    $allSafes = @()
    $offset = 0
    $limit = 100
    $consecutiveFailures = 0
    $maxConsecutiveFailures = 3
    $failedPageCount = 0
    $script:SafeListingFailedPageCount = 0

    LogOutput "Retrieving all safes..."

    while ($consecutiveFailures -lt $maxConsecutiveFailures) {
        $uri = "$($ConfOnboardingRuntime.PVWAGetSafesUrl)?offset=$offset&limit=$limit"
        LogDebug "Requesting safes: $uri"

        try {
            $response = Invoke-PVWARestMethod `
                -Uri $uri `
                -Headers @{'Authorization' = $ConfOnboardingRuntime.AuthTrimmed } `
                -TimeoutSec $ConfOnboardingRuntime.ConnectionTimeoutSeconds
        } catch {
            # Skip an exhausted page so later Safe-list pages can still be attempted.
            LogError "Failed to retrieve safes at offset $offset : $($_.Exception.Message)"
            $failedPageCount++
            $consecutiveFailures++
            $offset += $limit
            continue
        }

        if ([string]::IsNullOrWhiteSpace($response)) {
            $consecutiveFailures = 0
            LogOutput "No more safes at offset $offset"
            break
        }

        try {
            $safesData = $response | ConvertFrom-Json -ErrorAction Stop
        } catch {
            # PowerShell7 update: Include HTTP response shape for malformed or non-JSON replies.
            LogError "Failed to parse safes at offset $offset : $($_.Exception.Message). $(Get-PVWAResponseDiagnostic -Content $response)"
            $failedPageCount++
            $consecutiveFailures++
            $offset += $limit
            continue
        }

        $consecutiveFailures = 0

        if ($safesData.value -and $safesData.value.Count -gt 0) {
            $allSafes += $safesData.value
            $offset += $limit

            LogOutput "Retrieved $($safesData.value.Count) safes (total: $($allSafes.Count))"

            if (-not $ConfOnboardingRuntime.isAutosys) {
                Write-Progress -Activity "Retrieving Safes" -Status "$($allSafes.Count) safes" -PercentComplete -1
            }

            # A short page is final, avoiding one unnecessary request.
            if ($safesData.value.Count -lt $limit) { break }
        } else {
            break
        }
    }

    $script:SafeListingFailedPageCount = $failedPageCount

    if ($failedPageCount -gt 0) {
        LogWarn "Safe listing had $failedPageCount failed page(s) - the safe list may be incomplete."
    }
    if ($consecutiveFailures -ge $maxConsecutiveFailures) {
        LogError "Stopped retrieving safes after $maxConsecutiveFailures consecutive page failures."
    }

    LogOutput "Retrieved $($allSafes.Count) safes total"
    return $allSafes
}

# Retrieves the full extended-details user list from PVWA in one call and returns
# the parsed JSON response.
function Get-Users {
    [CmdletBinding()]
    param()

    try {
        # Extended details avoid separate calls for memberships and permissions.
        $response = Invoke-PVWARestMethod -Uri $ConfOnboardingRuntime.PVWAGetUsersUrl -Headers @{'Authorization' = $ConfOnboardingRuntime.AuthTrimmed } -TimeoutSec $ConfOnboardingRuntime.ConnectionTimeoutSeconds

        if ([string]::IsNullOrWhiteSpace($response)) {
            Write-Error "Failed to retrieve users - API returned no data" -ErrorAction Stop
        }

        try {
            return $response | ConvertFrom-Json -ErrorAction Stop
        } catch {
            # PowerShell7 update: Include safe metadata while suppressing valid JSON content.
            Write-Error "Failed to parse users JSON response: $($_.Exception.Message). $(Get-PVWAResponseDiagnostic -Content $response)" -ErrorAction Stop
        }

    } catch {
        Write-Error "Failed to retrieve users: $($_.Exception.Message)" -ErrorAction Stop
    }
}

# Entry point for the accounts report: validates the output path is writable, then
# delegates the actual scan/export to Get-AllAccounts.
function Process-AccountsReport {
    [CmdletBinding()]
    param()

    try {
        LogOutput "Starting accounts report generation..."

        $TargetFile = "Data_PasswordObjects_Bulk.csv"
        $OutputPath = Join-Path -Path $ConfOnboardingRuntime.ConfDirLogs -ChildPath $TargetFile

        # Fail before the long scan if the report destination is unavailable.
        $outputDirectory = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDirectory)) {
            Write-Error "Output directory does not exist: $outputDirectory" -ErrorAction Stop
        }

        # Prove write access before reading any Safe.
        try {
            Set-Content -Path $OutputPath -Value "Test write access" -ErrorAction Stop
            Remove-Item -Path $OutputPath -ErrorAction SilentlyContinue
        } catch {
            Write-Error "Cannot write to output file: $OutputPath. Error: $($_.Exception.Message)" -ErrorAction Stop
        }

        # Safe-scoped buffering keeps the normal path to one append per Safe.
        # PageSize of 1000 balances API performance with per-page processing cost.
        Get-AllAccounts -OutputPath $OutputPath
        $totalAccounts = $ConfOnboardingRuntime.AccountsResult

        LogOutput "Account Report completed: $totalAccounts accounts written to $OutputPath"

    } catch {
        LogError "Script execution failed: $($_.Exception.Message)"
        Write-Error -ErrorRecord $_ -ErrorAction Stop
    }
}

# Scans every non-system Safe for accounts and streams them to $OutputPath as CSV,
# one Safe at a time. After three consecutive transient Safe failures it verifies
# PVWA with one fresh login attempt before deciding whether scanning can continue.
# Sets $ConfOnboardingRuntime.AccountsResult.
function Get-AllAccounts {
    [CmdletBinding()]
    param(
        [string]$OutputPath = $null
    )

    $scriptStart = Get-Date
    $totalAccounts = 0
    $pageSize = 1000

    LogOutput "Starting account retrieval (PageSize: $pageSize)"

    if (-not $OutputPath) {
        Write-Error "OutputPath is required for account retrieval" -ErrorAction Stop
    }

    # Write the fixed header first so a zero-row report is still valid.
    $csvHeader = '"rowid","AccountName","Address","UserName","Platform","ModificationDate","ModifiedBy","LastUsedDate","LastUsedBy","Safe","CreatedBy","CreationDate","CPMStatus","Folder","LastTask","CPMErrorDetails","CPMDisabled","LastFailDate","LastSuccessVerification","DateTimeNow","ResetImmediately","ApplicationID","ConfigItemType","LastReconciledTime","PlatformAccountProperties"'
    # PowerShell7 update: Preserve the report's Windows-compatible UTF-8 BOM.
    Set-Content -Path $OutputPath -Value $csvHeader -Encoding utf8BOM

    # Enumerate first so exclusions happen before account paging begins.
    $allSafes = Get-AllSafes
    if (-not $allSafes -or $allSafes.Count -eq 0) {
        LogError "No safes retrieved - cannot enumerate accounts"
        $ConfOnboardingRuntime.AccountsResult = 0
        return
    }

    # Skip system Safes before making any account requests.
    $excludedPatterns = @('CPM*', 'Log*', 'Notification*', 'Pictures', 'PSM*', 'PVWA*', 'System*', 'VaultInternal*')

    $safesToProcess = @($allSafes | Where-Object {
        $name = $_.safeName
        if ([string]::IsNullOrWhiteSpace($name)) { return $false }
        foreach ($pattern in $excludedPatterns) {
            if ($name -like $pattern) { return $false }
        }
        return $true
    })

    $totalSafes = $safesToProcess.Count
    $excludedSafeCount = $allSafes.Count - $totalSafes
    LogOutput "Retrieved $($allSafes.Count) safes total, $totalSafes eligible after exclusions - beginning account retrieval"
    LogOutput "Skipped $excludedSafeCount safe(s) matching configured system-safe exclusions."

    # Keep failure categories separate so the final summary shows what was attempted.
    $failedSafes                  = [System.Collections.Generic.List[string]]::new()
    $partialSafes                 = [System.Collections.Generic.List[string]]::new()
    $skippedPVWAUnavailableCount = 0
    $skippedAccounts              = [System.Collections.Generic.List[string]]::new()

    $completedSafes = 0
    $consecutiveTransientSafeFailures = 0
    $maxConsecutiveSafeFailures = 3
    $pvwaAvailabilityFailureMessage = $null

    for ($safeIndex = 0; $safeIndex -lt $totalSafes; $safeIndex++) {
        # A fresh login distinguishes individual Safe failures from PVWA downtime.
        if ($consecutiveTransientSafeFailures -ge $maxConsecutiveSafeFailures) {
            LogWarn "$maxConsecutiveSafeFailures consecutive Safes failed with transient errors. Checking PVWA with one fresh login attempt."

            try {
                $null = Get-AuthToken -SingleAttempt
                $consecutiveTransientSafeFailures = 0
                LogOutput "PVWA login check succeeded. Continuing account retrieval."
            } catch {
                $skippedPVWAUnavailableCount = $totalSafes - $safeIndex
                $pvwaAvailabilityFailureMessage = $_.Exception.Message
                LogError "PVWA login check failed: $pvwaAvailabilityFailureMessage"
                LogError "Stopping account retrieval. $skippedPVWAUnavailableCount remaining safe(s) were not attempted."
                break
            }
        }

        $safe = $safesToProcess[$safeIndex]
        $safeName = $safe.safeName
        $safeId = if ($safe.safeUrlId) { $safe.safeUrlId } else { '(unknown id)' }
        $safeIdentifier = "name=$safeName id=$safeId"
        $completedSafes++

        $encodedSafeName = [Uri]::EscapeDataString($safeName)
        $uri = "$($ConfOnboardingRuntime.PVWAAccountsUrl)?filter=safeName eq ${encodedSafeName}&limit=$pageSize"

        $safeAccountCount  = 0
        $safeHadAnyPageData = $false
        $safeFailed        = $false
        $safeFailureWasTransient = $false
        $safeErrorMessage  = $null
        $safeCsvLines = [System.Collections.Generic.List[string]]::new()

        while ($uri) {
            $content = $null
            try {
                $content = Invoke-PVWARestMethod -Uri $uri `
                    -Headers @{ 'Authorization' = $ConfOnboardingRuntime.AuthTrimmed } `
                    -TimeoutSec $ConfOnboardingRuntime.ConnectionTimeoutSeconds `
                    -ReauthenticateOnConnectionClosed
            } catch {
                # The request helper records whether an exhausted failure was
                # transient so only connection-type failures affect the breaker.
                if ($_.Exception.Data -and $_.Exception.Data.Contains('PVWATransient')) {
                    $safeFailureWasTransient = [bool]$_.Exception.Data['PVWATransient']
                }
                # PowerShell7 update: Distinguish malformed JSON from HTML, empty or truncated responses.
                $safeErrorMessage = "$($_.Exception.Message). $(Get-PVWAResponseDiagnostic -Content $content)"
                LogError "Safe '$safeName': failed to retrieve accounts - $safeErrorMessage"
                $safeFailed = $true
                break
            }

            if ([string]::IsNullOrWhiteSpace($content)) { break }

            try {
                $accountsData = $content | ConvertFrom-Json -ErrorAction Stop
            } catch {
                $safeErrorMessage = $_.Exception.Message
                LogError "Safe '$safeName': could not parse accounts response - $safeErrorMessage"
                $safeFailed = $true
                break
            }

            if (-not $accountsData -or -not $accountsData.value -or $accountsData.value.Count -eq 0) { break }

            $safeHadAnyPageData = $true

            foreach ($Account in $accountsData.value) {
                if ($null -eq $Account) { continue }

                try {
                    $secretMgmt    = $Account.secretManagement
                    $platformProps = $Account.platformAccountProperties

                    $csvRow = @(
                        $Account.id
                        $Account.name
                        $Account.address
                        $Account.userName
                        $Account.platformId
                        (ConvertDate $secretMgmt.lastModifiedTime).Date
                        ''
                        ''
                        ''
                        $Account.safeName
                        ''
                        (ConvertDate $Account.createdTime).Date
                        $(if ($secretMgmt.status) { $secretMgmt.status } else { 'NotSet' })
                        ''
                        ''
                        $(if ($secretMgmt.manualManagementReason) { $secretMgmt.manualManagementReason } else { 'NotSet' })
                        $(if ($null -ne $secretMgmt.automaticManagementEnabled) { $secretMgmt.automaticManagementEnabled } else { 'NotSet' })
                        ''
                        (ConvertDate $secretMgmt.lastVerifiedTime).Date
                        ''
                        ''
                        $(if ($platformProps.ApplicationID) { $platformProps.ApplicationID } else { 'NotSet' })
                        $(if ($platformProps.ConfigItemType) { $platformProps.ConfigItemType } else { 'NotSet' })
                        (ConvertDate $secretMgmt.lastReconciledTime).Date
                        ''
                    )

                    $csvLine = ($csvRow | ForEach-Object {
                        $val = if ($null -eq $_) { '' } else { [string]$_ }
                        '"' + ($val -replace '"', '""') + '"'
                    }) -join ','

                    [void]$safeCsvLines.Add($csvLine)
                    $safeAccountCount++
                } catch {
                    # One malformed account is skipped and logged by id - it
                    # never corrupts the CSV or aborts the rest of the safe.
                    $acctId = if ($Account.id) { $Account.id } else { '(unknown id)' }
                    LogError "Safe '$safeName': skipped account id=$acctId - $($_.Exception.Message)"
                    [void]$skippedAccounts.Add("safe=$safeName id=$acctId")
                }
            }

            if ($accountsData.nextLink) {
                try {
                    $uri = Resolve-PVWANextLink `
                        -BaseUrl $ConfOnboardingRuntime.ConfPVWAURL `
                        -NextLink $accountsData.nextLink
                } catch {
                    $safeErrorMessage = $_.Exception.Message
                    LogError "Safe '$safeName': invalid accounts nextLink - $safeErrorMessage"
                    $safeFailed = $true
                    break
                }
            } else {
                $uri = $null
            }
        }

        # A successful Safe is written once after its final page. A failed Safe
        # is written here immediately after the failing page so partial rows survive.
        if ($safeCsvLines.Count -gt 0) {
            # PowerShell7 update: Preserve the report's Windows-compatible UTF-8 BOM.
            Add-Content -Path $OutputPath -Value $safeCsvLines -Encoding utf8BOM
            $totalAccounts += $safeCsvLines.Count
        }

        if ($safeFailed) {
            $safeFailureDetail = "$safeIdentifier error=$safeErrorMessage"
            if ($safeHadAnyPageData) {
                [void]$partialSafes.Add($safeFailureDetail)
                LogWarn "Safe '$safeName': partial - $safeAccountCount account(s) written before a page failed."
            } else {
                [void]$failedSafes.Add($safeFailureDetail)
            }

            if ($safeFailureWasTransient) {
                $consecutiveTransientSafeFailures++
            } else {
                $consecutiveTransientSafeFailures = 0
            }
        } else {
            $consecutiveTransientSafeFailures = 0
        }

        if (-not $ConfOnboardingRuntime.isAutosys) {
            $pct = [Math]::Min(100, [int](($completedSafes / $totalSafes) * 100))
            Write-Progress -Activity "Retrieving Accounts" `
                -Status "Safes: $completedSafes/$totalSafes | Accounts: $totalAccounts" `
                -PercentComplete $pct
        }

        if ($completedSafes % 50 -eq 0) {
            # Limit scheduled-job progress logs on vaults with thousands of Safes.
            LogOutput "Progress: $completedSafes/$totalSafes safes, $totalAccounts accounts"
        }
    }

    if (-not $ConfOnboardingRuntime.isAutosys) {
        Write-Progress -Activity "Retrieving Accounts" -Completed
    }

    $elapsed = (Get-Date) - $scriptStart
    LogOutput "Complete: $totalAccounts accounts from $completedSafes attempted Safe(s), $totalSafes eligible Safe(s) in $($elapsed.ToString('hh\:mm\:ss'))"

    # Summary entries are informational and never alter AccountsResult.
    if ($failedSafes.Count -gt 0) {
        LogWarn "Failed: $($failedSafes.Count) safe(s) failed entirely with no accounts retrieved."
        foreach ($failedSafe in $failedSafes) {
            LogWarn "FailedSafe: $failedSafe"
        }
    }
    if ($partialSafes.Count -gt 0) {
        LogWarn "Partial: $($partialSafes.Count) safe(s) returned some accounts before failing."
        foreach ($partialSafe in $partialSafes) {
            LogWarn "PartialSafe: $partialSafe"
        }
    }
    if ($skippedPVWAUnavailableCount -gt 0) {
        LogWarn "SkippedPVWAUnavailable: $skippedPVWAUnavailableCount safe(s) were not attempted after the PVWA login check failed."
    }
    if ($skippedAccounts.Count -gt 0) {
        LogWarn "SkippedAccounts: $($skippedAccounts.Count) account(s) skipped due to individual read/parse errors: $($skippedAccounts -join '; ')"
    }
    if ($script:SafeListingFailedPageCount -gt 0) {
        LogWarn "SafeListingFailedPages: $script:SafeListingFailedPageCount"
    }
    if ($failedSafes.Count -eq 0 -and $partialSafes.Count -eq 0 -and $skippedPVWAUnavailableCount -eq 0 -and $skippedAccounts.Count -eq 0 -and $script:SafeListingFailedPageCount -eq 0) {
        LogOutput "No failures during account retrieval."
    }

    $ConfOnboardingRuntime.AccountsResult = $totalAccounts

    if ($pvwaAvailabilityFailureMessage) {
        Write-Error "PVWA did not respond to the one-attempt login check: $pvwaAvailabilityFailureMessage" -ErrorAction Stop
    }
}

# Exports the vault user list to two CSVs: group memberships and user attribute
# details, kept separate so each has a focused, stable column set.
function Process-UsersReport {
    [CmdletBinding()]
    param()

    try {
        LogOutput "Starting users report generation..."

        $TargetFileDetails = "Data_UserList_Details.csv"
        $TargetFileGroups = "Data_UserList_GroupMemberships.csv"

        $GetUsersResponse = Get-Users

        if ($GetUsersResponse -and $GetUsersResponse.Users) {
            # Keep memberships separate so consumers can use a focused group feed.
            $GetUsersResponse.Users | Select-Object -Property id, username, 
                @{Name = "GroupMembership"; Expression = { ($_.groupsMembership.groupName -join ';') }},
                source, userType, suspended |
                # PowerShell7 update: Preserve the existing CSV BOM for downstream Windows tools.
                Export-Csv -Path (Join-Path -Path $ConfOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileGroups) -NoTypeInformation -UseCulture -Encoding utf8BOM -Force

            LogOutput "Users Group Memberships Report written to $(Join-Path -Path $ConfOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileGroups)"

            # Join authorization arrays so CSV does not contain a type name.
            foreach ($User in $GetUsersResponse.Users) {
                $User.vaultAuthorization = [String]$User.vaultAuthorization
            }

            # Keep user attributes separate from the membership feed.
            $GetUsersResponse.Users | Select-Object -Property username, id, source, userType, vaultAuthorization, suspended |
                # PowerShell7 update: Preserve the existing CSV BOM for downstream Windows tools.
                Export-Csv -Path (Join-Path -Path $ConfOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileDetails) -NoTypeInformation -UseCulture -Encoding utf8BOM -Force

            LogOutput "Users Details Report written to $(Join-Path -Path $ConfOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileDetails)"
        } else {
            LogError "Failed to retrieve users data"
            Write-Error "No users data retrieved from API" -ErrorAction Stop
        }

    } catch {
        LogError "Users report generation failed: $($_.Exception.Message)"
        Write-Error -ErrorRecord $_ -ErrorAction Stop
    }
}

# Exports Safe details (retention policy, creator, timestamps, etc.) for every
# Safe to a single CSV.
function Process-SafesReport {
    [CmdletBinding()]
    param()

    try {
        LogOutput "Starting safes report generation..."

        $TargetFile = "Data_SafeDetails_Expanded.csv"

        $allSafes = Get-AllSafes

        if ($allSafes -and $allSafes.Count -gt 0) {
            # Select stable fields so report columns do not follow API expansion.
            $allSafes | Select-Object -Property SafeMember, SafeName, Description, Location, `
                @{Name = "CreatedBy"; Expression = { $_.Creator.name } },
                    olaEnabled,
                    ManagingCPM,
                    NumberOfDaysRetention,
                    NumberOfVersionsRetention,
                    AutoPurgeEnabled,
                @{Name = 'creationTime'; Expression = { (ConvertDate $_.creationTime).Date } },
                @{Name = 'lastModificationTime2'; Expression = { (ConvertDate $_.lastModificationTime).Date } },
                isExpiredMember |
                # PowerShell7 update: Preserve the existing CSV BOM for downstream Windows tools.
                Export-Csv -Path (Join-Path -Path $ConfOnboardingRuntime.ConfDirLogs -ChildPath $TargetFile) -NoTypeInformation -UseCulture -Encoding utf8BOM -Force

            LogOutput "Safes Report written to $(Join-Path -Path $ConfOnboardingRuntime.ConfDirLogs -ChildPath $TargetFile)"
        } else {
            LogError "Failed to retrieve safes data or no safes found"
            Write-Error "No safes data available" -ErrorAction Stop
        }

    } catch {
        LogError "Safes report generation failed: $($_.Exception.Message)"
        Write-Error -ErrorRecord $_ -ErrorAction Stop
    }
}

# PowerShell7 update: Use an OS file lock to prevent concurrent runs corrupting fixed report filenames.
function Enter-CybOnboardingRunLock {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$LockPath)

    $lockDirectory = Split-Path -Path $LockPath -Parent
    if ($lockDirectory -and -not (Test-Path -LiteralPath $lockDirectory -PathType Container)) {
        Write-Error "Run-lock directory does not exist: $lockDirectory" -ErrorAction Stop
    }

    try {
        return [System.IO.File]::Open(
            $LockPath,
            [System.IO.FileMode]::OpenOrCreate,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
    } catch [System.IO.IOException] {
        Write-Error "Another Cyb-User-Onboarding run is already active. Lock: $LockPath" -ErrorAction Stop
    }
}

# PowerShell7 update: Releasing the handle makes the lock safe after normal or abnormal process exit.
function Exit-CybOnboardingRunLock {
    [CmdletBinding()]
    param([AllowNull()][System.IO.FileStream]$LockHandle)

    if ($null -ne $LockHandle) { $LockHandle.Dispose() }
}

# PowerShell7 update: Explicitly release the PVWA session created for unattended reporting.
function Close-PVWASession {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace([string]$ConfOnboardingRuntime.AuthTrimmed) -or
        [string]::IsNullOrWhiteSpace([string]$ConfOnboardingRuntime.PVWALogoffUrl)) { return }

    try {
        $null = Invoke-PVWARestMethod -Uri $ConfOnboardingRuntime.PVWALogoffUrl -Method POST `
            -Headers @{ Authorization = $ConfOnboardingRuntime.AuthTrimmed } `
            -TimeoutSec $ConfOnboardingRuntime.ConnectionTimeoutSeconds -MaxAttempts 1
        LogDebug 'PVWA session logged off.'
    } catch {
        LogWarn "PVWA logoff failed: $($_.Exception.Message)"
    } finally {
        $ConfOnboardingRuntime.AuthTrimmed = $null
    }
}

# Forces a garbage collection pass at the end of a run, so a long report doesn't
# leave a large working set behind for the rest of the scheduled job.
function Cleanup {
    Close-PVWASession
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

# CyberArk user information functions.

# Logs on to PVWA with a pre-built authentication body and stores the resulting
# token in $ConfOnboardingRuntime.Header for subsequent calls.
Function New-Login {
    Param(
        [string]$Authentication
    )

    Begin {
        $DebugPreference = 'SilentlyContinue'
        if ($PSBoundParameters['Debug'] -and $PSBoundParameters.Debug) {
            $DebugPreference = 'Continue'  # Write-Debug will pause interactively without this
        }

        $loginCybURI = "$($ConfOnboardingRuntime.ConfPVWAURL)/API/auth/Cyberark/Logon"
        $headers = $null
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Content-Type", "application/json")
        # Force UTF-8 so kanji/multi-byte chars round-trip correctly
        $headers.Add("Accept-Charset", "utf-8")
    }

    Process {
        $result = $null
        try {
            # PowerShell7 update: Request an independent PVWA session for concurrent scheduled processes.
            $authenticationBody = $Authentication | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $authenticationBody.concurrentSession = $true
            $Authentication = $authenticationBody | ConvertTo-Json -Compress

            $result = Invoke-RestMethod -Method Post -Uri $loginCybURI -Headers $headers -ContentType 'application/json; charset=utf-8' `
                -Body $Authentication -HttpVersion 2.0 `
                -ConnectionTimeoutSeconds 300 -OperationTimeoutSeconds 300 -ErrorAction Stop
            $Message = "INFO: CyberArk Vault login successful"
            $headers.Add("Authorization", $result)
            $ConfOnboardingRuntime.Header = $headers
        } catch {
            # PowerShell7 update: Include nested HttpClient errors when no response body exists.
            $body = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { Get-PVWAExceptionDetail -Exception $_.Exception }
            $Message = "ERROR: Unable to connect to the API - $body"
            Start-Sleep -Seconds 1
            return [PSCustomObject]@{ Return = $false; Message = $Message }
        }
        return [PSCustomObject]@{ Return = $true; Message = $Message }
    }
}

# Retrieves the /API/Users list using the session already stored in
# $ConfOnboardingRuntime.Header (set by New-Login). Returns a Success/Data/Message
# object rather than terminating, so callers can branch on failure without try/catch.
function Get-AllUsers {
    [CmdletBinding()]
    param()

    $DebugPreference = 'SilentlyContinue'
    if ($PSBoundParameters['Debug'] -and $PSBoundParameters.Debug) {
        $DebugPreference = 'Continue'  # Write-Debug will pause interactively without this
    }

    try {
        LogDebug "Invoke-RestMethod -Uri `"$($ConfOnboardingRuntime.ConfPVWAURL)/API/Users`" -Method GET"
        # PowerShell7 update: Use HTTP/2 and separate connection/operation timeouts.
        $Response = Invoke-RestMethod -Uri "$($ConfOnboardingRuntime.ConfPVWAURL)/API/Users" -Method GET `
            -Headers $ConfOnboardingRuntime.Header -ContentType 'application/json; charset=utf-8' `
            -HttpVersion 2.0 -ConnectionTimeoutSeconds 300 -OperationTimeoutSeconds 300 `
            -Verbose:$false -Debug:$false -ErrorAction Stop

        LogDebug "GOT $($Response.Total) users"
        return [PSCustomObject]@{ Success = $true; Data = $Response; Message = 'OK' }
    } catch {
        # Surface full error context
        $statusCode = $null
        $responseBody = $null
        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
            $responseBody = $_.ErrorDetails.Message
        }
        $exType = $_.Exception.GetType().FullName
        $detail = "Type=$exType; Status=$statusCode; Exception=$($_.Exception.Message); Body=$responseBody"
        return [PSCustomObject]@{ Success = $false; Data = $null; Message = "Failed to get users: $detail" }
    }
}

# Retrieves one user's full detail record (including group memberships, filtered
# through $ConfOnboardingRuntime.ExcludedGroupPatterns) with retry on timeouts/5xx
# and a single automatic re-login on a 401. Returns a Success/Data/Message/GroupCount
# object rather than terminating, so a per-user failure doesn't need its own try/catch.
function Get-UserDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$UserId,
        [Parameter(Mandatory)]
        [string]$UserName
    )

    $DebugPreference = 'SilentlyContinue'

    $uri = "$($ConfOnboardingRuntime.ConfPVWAURL)/API/Users/$UserId"
    $maxRetries = 3
    $attempt = 0
    $reloginAttempted = $false   # 401 re-login is allowed once only

    while ($attempt -lt $maxRetries) {
        $attempt++
        try {
            # PowerShell7 update: Use HTTP/2 and separate connection/operation timeouts.
            $rawResponse = Invoke-WebRequest -Uri $uri -Method GET `
                -Headers $ConfOnboardingRuntime.Header `
                -ContentType 'application/json; charset=utf-8' `
                -HttpVersion 2.0 -ConnectionTimeoutSeconds 60 -OperationTimeoutSeconds 60 `
                -Verbose:$false -Debug:$false -ErrorAction Stop

            # Force UTF-8 decoding for kanji - Invoke-RestMethod can mis-detect encoding
            $bytes = $rawResponse.RawContentStream.ToArray()
            $jsonText = [System.Text.Encoding]::UTF8.GetString($bytes)
            $Response = $jsonText | ConvertFrom-Json -ErrorAction Stop

            # Strip exact-name and wildcard groups from the shared exclusion configuration.
            if ($ConfOnboardingRuntime.ExcludedGroupPatterns -and @($Response.groupsMembership).Count -gt 0) {
                $Response.groupsMembership = @(
                    $Response.groupsMembership | Where-Object {
                        $gn = $_.groupName
                        $keep = $true
                        foreach ($pattern in $ConfOnboardingRuntime.ExcludedGroupPatterns) {
                            if ($gn -like $pattern) { $keep = $false; break }
                        }
                        $keep
                    }
                )
            }

            # Count groups AFTER exclusions. A user with zero groups left - whether they
            # had none to begin with, or only excluded ones - counts as NoGroupMembership.
            $groupCount = @($Response.groupsMembership).Count

            return [PSCustomObject]@{
                Success    = $true
                Data       = $Response
                Message    = 'OK'
                GroupCount = $groupCount
            }

        } catch {
            # Invoke-WebRequest with -ErrorAction Stop wraps HTTP errors as WebException,
            # but timeouts and DNS failures may surface as different types. Handle all here.
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            $responseBody = $null
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                $responseBody = $_.ErrorDetails.Message
            }
            $exType = $_.Exception.GetType().FullName
            $isTimeout = ($_.Exception.Status -eq 'Timeout') -or ($_.Exception.Message -match 'time(d )?out')

            # 401 = session expired (rare with constant calls). Re-login once only.
            if ($statusCode -eq 401) {
                if ($reloginAttempted) {
                    return [PSCustomObject]@{ Success = $false; Data = $null; Message = "Repeated 401 for user $UserId ($UserName) after re-login - giving up" }
                }
                $reloginAttempted = $true
                LogWarn "401 on user $UserId ($UserName) - re-login and retry once"
                $loginSplat = $ConfOnboardingRuntime.LoginSplat
                $relogin = New-Login -Authentication $ConfOnboardingRuntime.PVWAAuthBody.AuthBody @loginSplat
                if (-not $relogin.Return) {
                    return [PSCustomObject]@{ Success = $false; Data = $null; Message = "Re-login failed for user $UserId ($UserName): $($relogin.Message)" }
                }
                $attempt--   # don't let the re-login consume the general retry budget
                continue
            }

            # Timeout or transient - back off and retry
            if ($statusCode -in @(408, 429, 500, 502, 503, 504) -or $isTimeout) {
                $backoff = [Math]::Pow(2, $attempt)
                LogWarn "Status=$statusCode Timeout=$isTimeout on user $UserId ($UserName) attempt $attempt - backing off ${backoff}s"
                Start-Sleep -Seconds $backoff
                continue
            }

            # Non-retryable
            $detail = "Type=$exType; Status=$statusCode; Exception=$($_.Exception.Message); Body=$responseBody"
            return [PSCustomObject]@{ Success = $false; Data = $null; Message = "Failed to retrieve user details for $UserName (ID=$UserId): $detail" }
        }
    }

    return [PSCustomObject]@{ Success = $false; Data = $null; Message = "Failed to retrieve user details for $UserName (ID=$UserId): exhausted $maxRetries retries" }
}

Export-ModuleMember -Function @(
    'Set-GlobalPreferences'
    'LogStartScript'
    'LogOutput'
    'LogError'
    'LogWarn'
    'LogDebug'
    'ConvertDate'
    'Initialize-CybOnboardingContext'
    'Escape-LDAPFilter'
    'Resolve-GroupDN'
    'Invoke-PVWARestMethod'
    'Get-AuthToken'
    'Get-AllSafes'
    'Get-Users'
    'Process-AccountsReport'
    'Get-AllAccounts'
    'Process-UsersReport'
    'Process-SafesReport'
    'Enter-CybOnboardingRunLock'
    'Exit-CybOnboardingRunLock'
    'Close-PVWASession'
    'Cleanup'
    'New-Login'
    'Get-AllUsers'
    'Get-UserDetails'
) -Variable @(
    'ConfLegacyConfigurationModulePath'
    'ConfADConfigurationModuleName'
    'ConfSafeScanLogPath'
    'ConfPVWAEndpointSuffixes'
    'ConfUserInformationExcludedGroupPatterns'
    'ConfUserGroupAssignmentConfig'
    'ConfHumanUserScanConfig'
    'ConfADDomains'
    'ConfADGroups'
)
