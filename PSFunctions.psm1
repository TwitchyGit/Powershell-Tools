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
    throw "Configuration module not found: $configurationModulePath"
}

# Import locally so mutable runtime state stays scoped to this function module.
Import-Module -Name $configurationModulePath -Force -Scope Local -ErrorAction Stop

function Initialize-CybOnboardingContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration
    )

    # Reject unknown keys so configuration errors fail before any API request.
    foreach ($entry in $Configuration.GetEnumerator()) {
        if (-not $CybOnboardingRuntime.ContainsKey($entry.Key)) {
            throw "Unsupported onboarding context value: $($entry.Key)"
        }

        $CybOnboardingRuntime[$entry.Key] = $entry.Value
    }
}

# Active Directory helpers.

function Escape-LDAPFilter {
  param([string]$Value)
  $Value = $Value -replace '\\', '\5c'
  $Value = $Value -replace '\*', '\2a'
  $Value = $Value -replace '\(', '\28'
  $Value = $Value -replace '\)', '\29'
  $Value = $Value -replace '\x00', '\00'
  return $Value
}

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

    $msg = $ErrorRecord.Exception.Message

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
            throw "PVWA nextLink is not a valid absolute URI: $NextLink"
        }
        if ($absoluteUri.Scheme -notin @('http', 'https')) {
            throw "PVWA nextLink uses an unsupported URI scheme: $NextLink"
        }
        if (-not $absoluteUri.Scheme.Equals($baseUri.Scheme, [StringComparison]::OrdinalIgnoreCase) -or
            -not $absoluteUri.Authority.Equals($baseUri.Authority, [StringComparison]::OrdinalIgnoreCase)) {
            throw "PVWA nextLink points outside the configured PVWA host: $NextLink"
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
        [int]$TimeoutSec = 300
    )

    $attempt = 0
    $lastError = $null

    while ($attempt -lt $script:PVWAMaxAttempts) {
        $attempt++

        try {
            LogDebug "Attempt $attempt of $script:PVWAMaxAttempts for: $Uri"

            $requestParams = @{
                Uri             = $Uri
                Method          = $Method
                Headers         = $Headers
                ContentType     = "application/json"
                TimeoutSec      = $TimeoutSec
                UseBasicParsing = $true
            }

            if ($Body) { $requestParams.Body = $Body }

            $response = Invoke-WebRequest @requestParams
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
            }

            LogError "Attempt $attempt failed for $Uri - Status: $statusCode, Error: $($_.Exception.Message)"

            $isTransient = Test-PVWATransientError -ErrorRecord $_ -StatusCode $statusCode

            if (-not $isTransient) {
                $failure = [System.Exception]::new(
                    "Non-retryable error calling ${Uri}: $($_.Exception.Message)",
                    $_.Exception
                )
                $failure.Data['PVWATransient'] = $false
                throw $failure
            }

            if ($attempt -ge $script:PVWAMaxAttempts) {
                break
            }

            # Re-authenticate on 401 before the next attempt - the retry still
            # counts against the fixed attempt limit like any other transient failure.
            if ($statusCode -eq 401 -and $Headers.ContainsKey('Authorization')) {
                LogOutput "Re-authenticating..."
                try {
                    $CybOnboardingRuntime.AuthTrimmed = Get-AuthToken
                    $Headers['Authorization'] = $CybOnboardingRuntime.AuthTrimmed
                } catch {
                    $failure = [System.Exception]::new(
                        "Re-authentication failed calling ${Uri}: $($_.Exception.Message)",
                        $_.Exception
                    )
                    $failure.Data['PVWATransient'] = $true
                    throw $failure
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
    throw $failure
}

function Get-AuthToken {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $CybOnboardingRuntime.ConfAccountCredFile)) {
        throw "Credential file not found: $($CybOnboardingRuntime.ConfAccountCredFile)"
    }

    try {
        $PVWACreds = Import-Clixml -Path $CybOnboardingRuntime.ConfAccountCredFile
        
        if (-not $PVWACreds -or -not $PVWACreds.UserName -or -not $PVWACreds.Password) {
            throw "Invalid credentials in file"
        }

        $AuthBody = @{
            username = $PVWACreds.UserName
            password = $PVWACreds.GetNetworkCredential().Password
        } | ConvertTo-Json

        LogDebug "Authenticating as: $($PVWACreds.UserName)"

        $authResponse = Invoke-PVWARestMethod `
            -Uri $CybOnboardingRuntime.PVWALogonUrl `
            -Method "POST" `
            -Body $AuthBody `
            -TimeoutSec $CybOnboardingRuntime.ConnectionTimeoutSeconds

        if (-not $authResponse) {
            throw "Authentication failed - no token received"
        }

        $token = $authResponse -replace '"', ''
        $CybOnboardingRuntime.AuthTrimmed = $token
        LogDebug "Authentication successful"
        return $token

    } catch {
        throw "Authentication failed: $($_.Exception.Message)"
    } finally {
        if ($PVWACreds) {
            $PVWACreds.Password.Dispose()
        }
    }
}

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
        $uri = "$($CybOnboardingRuntime.PVWAGetSafesUrl)?offset=$offset&limit=$limit"
        LogDebug "Requesting safes: $uri"

        try {
            $response = Invoke-PVWARestMethod `
                -Uri $uri `
                -Headers @{'Authorization' = $CybOnboardingRuntime.AuthTrimmed } `
                -TimeoutSec $CybOnboardingRuntime.ConnectionTimeoutSeconds
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
            LogError "Failed to parse safes at offset $offset : $($_.Exception.Message)"
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

            if (-not $CybOnboardingRuntime.isAutosys) {
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

function Get-Users {
    [CmdletBinding()]
    param()

    try {
        # Extended details avoid separate calls for memberships and permissions.
        $response = Invoke-PVWARestMethod -Uri $CybOnboardingRuntime.PVWAGetUsersUrl -Headers @{'Authorization' = $CybOnboardingRuntime.AuthTrimmed } -TimeoutSec $CybOnboardingRuntime.ConnectionTimeoutSeconds

        if ([string]::IsNullOrWhiteSpace($response)) {
            throw "Failed to retrieve users - API returned no data"
        }

        try {
            return $response | ConvertFrom-Json -ErrorAction Stop
        } catch {
            # Safe string truncation - compatible with all PowerShell versions
            if ($response) {
                $responsePreview = $response.Substring(0, [Math]::Min(200, $response.Length))
            } else {
                $responsePreview = "(null)"
            }
            throw "Failed to parse users JSON response: $($_.Exception.Message). Response preview: $responsePreview"
        }

    } catch {
        throw "Failed to retrieve users: $($_.Exception.Message)"
    }
}

function Process-AccountsReport {
    [CmdletBinding()]
    param()

    try {
        LogOutput "Starting accounts report generation..."

        $TargetFile = "Data_PasswordObjects_Bulk.csv"
        $OutputPath = Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFile

        # Fail before the long scan if the report destination is unavailable.
        $outputDirectory = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDirectory)) {
            throw "Output directory does not exist: $outputDirectory"
        }

        # Prove write access before reading any Safe.
        try {
            Set-Content -Path $OutputPath -Value "Test write access" -ErrorAction Stop
            Remove-Item -Path $OutputPath -ErrorAction SilentlyContinue
        } catch {
            throw "Cannot write to output file: $OutputPath. Error: $($_.Exception.Message)"
        }

        # Safe-scoped buffering keeps the normal path to one append per Safe.
        # PageSize of 1000 balances API performance with per-page processing cost.
        Get-AllAccounts -OutputPath $OutputPath
        $totalAccounts = $CybOnboardingRuntime.AccountsResult

        LogOutput "Account Report completed: $totalAccounts accounts written to $OutputPath"

    } catch {
        LogError "Script execution failed: $($_.Exception.Message)"
        throw
    }
}

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
        throw "OutputPath is required for account retrieval"
    }

    # Write the fixed header first so a zero-row report is still valid.
    $csvHeader = '"rowid","AccountName","Address","UserName","Platform","ModificationDate","ModifiedBy","LastUsedDate","LastUsedBy","Safe","CreatedBy","CreationDate","CPMStatus","Folder","LastTask","CPMErrorDetails","CPMDisabled","LastFailDate","LastSuccessVerification","DateTimeNow","ResetImmediately","ApplicationID","ConfigItemType","LastReconciledTime","PlatformAccountProperties"'
    Set-Content -Path $OutputPath -Value $csvHeader -Encoding UTF8

    # Enumerate first so exclusions happen before account paging begins.
    $allSafes = Get-AllSafes
    if (-not $allSafes -or $allSafes.Count -eq 0) {
        LogError "No safes retrieved - cannot enumerate accounts"
        $CybOnboardingRuntime.AccountsResult = 0
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
    LogOutput "Retrieved $($allSafes.Count) safes total, $totalSafes eligible after exclusions - beginning account retrieval"

    # Keep failure categories separate so the final summary shows what was attempted.
    $failedSafes        = [System.Collections.Generic.List[string]]::new()
    $partialSafes       = [System.Collections.Generic.List[string]]::new()
    $skippedCircuitOpen = [System.Collections.Generic.List[string]]::new()
    $skippedAccounts    = [System.Collections.Generic.List[string]]::new()

    $completedSafes = 0
    $consecutiveTransientSafeFailures = 0
    $maxConsecutiveSafeFailures = 3

    for ($safeIndex = 0; $safeIndex -lt $totalSafes; $safeIndex++) {
        # Avoid hours of retries after three transient Safe failures.
        if ($consecutiveTransientSafeFailures -ge $maxConsecutiveSafeFailures) {
            for ($remainingIndex = $safeIndex; $remainingIndex -lt $totalSafes; $remainingIndex++) {
                $skippedSafe = $safesToProcess[$remainingIndex]
                $skippedSafeId = if ($skippedSafe.safeUrlId) { $skippedSafe.safeUrlId } else { '(unknown id)' }
                [void]$skippedCircuitOpen.Add("name=$($skippedSafe.safeName) id=$skippedSafeId")
            }

            LogError "Circuit breaker opened after $maxConsecutiveSafeFailures consecutive Safes failed with transient errors. Skipping $($skippedCircuitOpen.Count) remaining Safe(s)."
            break
        }

        $safe = $safesToProcess[$safeIndex]
        $safeName = $safe.safeName
        $safeId = if ($safe.safeUrlId) { $safe.safeUrlId } else { '(unknown id)' }
        $safeIdentifier = "name=$safeName id=$safeId"
        $completedSafes++

        $encodedSafeName = [Uri]::EscapeDataString($safeName)
        $uri = "$($CybOnboardingRuntime.PVWAAccountsUrl)?filter=safeName eq ${encodedSafeName}&limit=$pageSize"

        $safeAccountCount  = 0
        $safeHadAnyPageData = $false
        $safeFailed        = $false
        $safeFailureWasTransient = $false
        $safeCsvLines = [System.Collections.Generic.List[string]]::new()

        while ($uri) {
            try {
                $content = Invoke-PVWARestMethod -Uri $uri `
                    -Headers @{ 'Authorization' = $CybOnboardingRuntime.AuthTrimmed } `
                    -TimeoutSec $CybOnboardingRuntime.ConnectionTimeoutSeconds
            } catch {
                # The request helper records whether an exhausted failure was
                # transient so only connection-type failures affect the breaker.
                if ($_.Exception.Data -and $_.Exception.Data.Contains('PVWATransient')) {
                    $safeFailureWasTransient = [bool]$_.Exception.Data['PVWATransient']
                }
                LogError "Safe '$safeName': failed to retrieve accounts - $($_.Exception.Message)"
                $safeFailed = $true
                break
            }

            if ([string]::IsNullOrWhiteSpace($content)) { break }

            try {
                $accountsData = $content | ConvertFrom-Json -ErrorAction Stop
            } catch {
                LogError "Safe '$safeName': could not parse accounts response - $($_.Exception.Message)"
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
                        -BaseUrl $CybOnboardingRuntime.ConfPVWAURL `
                        -NextLink $accountsData.nextLink
                } catch {
                    LogError "Safe '$safeName': invalid accounts nextLink - $($_.Exception.Message)"
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
            Add-Content -Path $OutputPath -Value $safeCsvLines -Encoding UTF8
            $totalAccounts += $safeCsvLines.Count
        }

        if ($safeFailed) {
            if ($safeHadAnyPageData) {
                [void]$partialSafes.Add($safeIdentifier)
                LogWarn "Safe '$safeName': partial - $safeAccountCount account(s) written before a page failed."
            } else {
                [void]$failedSafes.Add($safeIdentifier)
            }

            if ($safeFailureWasTransient) {
                $consecutiveTransientSafeFailures++
            } else {
                $consecutiveTransientSafeFailures = 0
            }
        } else {
            $consecutiveTransientSafeFailures = 0
        }

        if (-not $CybOnboardingRuntime.isAutosys) {
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

    if (-not $CybOnboardingRuntime.isAutosys) {
        Write-Progress -Activity "Retrieving Accounts" -Completed
    }

    $elapsed = (Get-Date) - $scriptStart
    LogOutput "Complete: $totalAccounts accounts from $completedSafes attempted Safe(s), $totalSafes eligible Safe(s) in $($elapsed.ToString('hh\:mm\:ss'))"

    # Summary entries are informational and never alter AccountsResult.
    if ($failedSafes.Count -gt 0) {
        LogWarn "Failed: $($failedSafes.Count) safe(s) failed entirely (no accounts retrieved): $($failedSafes -join ', ')"
    }
    if ($partialSafes.Count -gt 0) {
        LogWarn "Partial: $($partialSafes.Count) safe(s) partially failed (some pages retrieved before a failure): $($partialSafes -join ', ')"
    }
    if ($skippedCircuitOpen.Count -gt 0) {
        LogWarn "SkippedCircuitOpen: $($skippedCircuitOpen.Count) safe(s) were not attempted: $($skippedCircuitOpen -join ', ')"
    }
    if ($skippedAccounts.Count -gt 0) {
        LogWarn "SkippedAccounts: $($skippedAccounts.Count) account(s) skipped due to individual read/parse errors: $($skippedAccounts -join '; ')"
    }
    if ($script:SafeListingFailedPageCount -gt 0) {
        LogWarn "SafeListingFailedPages: $script:SafeListingFailedPageCount"
    }
    if ($failedSafes.Count -eq 0 -and $partialSafes.Count -eq 0 -and $skippedCircuitOpen.Count -eq 0 -and $skippedAccounts.Count -eq 0 -and $script:SafeListingFailedPageCount -eq 0) {
        LogOutput "No failures during account retrieval."
    }

    $CybOnboardingRuntime.AccountsResult = $totalAccounts
}

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
                Export-Csv -Path (Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileGroups) -NoTypeInformation -UseCulture -Force

            LogOutput "Users Group Memberships Report written to $(Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileGroups)"

            # Join authorization arrays so CSV does not contain a type name.
            foreach ($User in $GetUsersResponse.Users) {
                $User.vaultAuthorization = [String]$User.vaultAuthorization
            }

            # Keep user attributes separate from the membership feed.
            $GetUsersResponse.Users | Select-Object -Property username, id, source, userType, vaultAuthorization, suspended |
                Export-Csv -Path (Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileDetails) -NoTypeInformation -UseCulture -Force

            LogOutput "Users Details Report written to $(Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileDetails)"
        } else {
            LogError "Failed to retrieve users data"
            throw "No users data retrieved from API"
        }

    } catch {
        LogError "Users report generation failed: $($_.Exception.Message)"
        throw
    }
}

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
                Export-Csv -Path (Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFile) -NoTypeInformation -UseCulture -Force

            LogOutput "Safes Report written to $(Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFile)"
        } else {
            LogError "Failed to retrieve safes data or no safes found"
            throw "No safes data available"
        }

    } catch {
        LogError "Safes report generation failed: $($_.Exception.Message)"
        throw
    }
}

function Cleanup {
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}

# CyberArk user information functions.

Function New-Login {
    Param(
        [string]$Authentication
    )

    Begin {
        $DebugPreference = 'SilentlyContinue'
        if ($PSBoundParameters['Debug'] -and $PSBoundParameters.Debug) {
            $DebugPreference = 'Continue'  # Write-Debug will pause interactively without this
        }

        $loginCybURI = "$($CybOnboardingRuntime.ConfPVWAURL)/API/auth/Cyberark/Logon"
        $headers = $null
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Content-Type", "application/json")
        # Force UTF-8 so kanji/multi-byte chars round-trip correctly
        $headers.Add("Accept-Charset", "utf-8")
    }

    Process {
        $result = $null
        try {
            $result = Invoke-RestMethod -Method Post -Uri $loginCybURI -Headers $headers -ContentType 'application/json; charset=utf-8' `
                -Body $Authentication -UseBasicParsing -ErrorAction Stop
            $Message = "INFO: CyberArk Vault login successful"
            $headers.Add("Authorization", $result)
            $CybOnboardingRuntime.Header = $headers
        } catch {
            $body = $_.ErrorDetails.Message
            if ($null -ne $body) {
                $Message = "ERROR: Unable to connect to the API - $body"
            } else {
                $body = $body -replace '[{"}]' -replace ',', " "
                $Message = "ERROR: $body"
            }
            Start-Sleep -Seconds 1
            return [PSCustomObject]@{ Return = $false; Message = $Message }
        }
        return [PSCustomObject]@{ Return = $true; Message = $Message }
    }
}

function Get-AllUsers {
    [CmdletBinding()]
    param()

    $DebugPreference = 'SilentlyContinue'
    if ($PSBoundParameters['Debug'] -and $PSBoundParameters.Debug) {
        $DebugPreference = 'Continue'  # Write-Debug will pause interactively without this
    }

    try {
        Write-Debug "Invoke-RestMethod -Uri `"$($CybOnboardingRuntime.ConfPVWAURL)/API/Users`" -Method GET"
        # Increased timeout - large user lists can take a while server-side
        $Response = Invoke-RestMethod -Uri "$($CybOnboardingRuntime.ConfPVWAURL)/API/Users" -Method GET `
            -Headers $CybOnboardingRuntime.Header -UseBasicParsing -ContentType 'application/json; charset=utf-8' `
            -TimeoutSec 300 `
            -Verbose:$false -Debug:$false -ErrorAction Stop

        Write-Debug "GOT $($Response.Total) users"
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

function Get-UserDetails {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$UserId,
        [Parameter(Mandatory)]
        [string]$UserName
    )

    $DebugPreference = 'SilentlyContinue'

    $uri = "$($CybOnboardingRuntime.ConfPVWAURL)/API/Users/$UserId"
    $maxRetries = 3
    $attempt = 0
    $reloginAttempted = $false   # 401 re-login is allowed once only

    while ($attempt -lt $maxRetries) {
        $attempt++
        try {
            $rawResponse = Invoke-WebRequest -Uri $uri -Method GET `
                -Headers $CybOnboardingRuntime.Header -UseBasicParsing `
                -ContentType 'application/json; charset=utf-8' `
                -TimeoutSec 60 `
                -Verbose:$false -Debug:$false -ErrorAction Stop

            # Force UTF-8 decoding for kanji - Invoke-RestMethod can mis-detect encoding
            $bytes = $rawResponse.RawContentStream.ToArray()
            $jsonText = [System.Text.Encoding]::UTF8.GetString($bytes)
            $Response = $jsonText | ConvertFrom-Json

            # Strip exact-name and wildcard groups from the shared exclusion configuration.
            if ($CybOnboardingRuntime.ExcludedGroupPatterns -and @($Response.groupsMembership).Count -gt 0) {
                $Response.groupsMembership = @(
                    $Response.groupsMembership | Where-Object {
                        $gn = $_.groupName
                        $keep = $true
                        foreach ($pattern in $CybOnboardingRuntime.ExcludedGroupPatterns) {
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
                LogMessage("WARN: 401 on user $UserId ($UserName) - re-login and retry once")
                $loginSplat = $CybOnboardingRuntime.LoginSplat
                $relogin = New-Login -Authentication $CybOnboardingRuntime.PVWAAuthBody.AuthBody @loginSplat
                if (-not $relogin.Return) {
                    return [PSCustomObject]@{ Success = $false; Data = $null; Message = "Re-login failed for user $UserId ($UserName): $($relogin.Message)" }
                }
                $attempt--   # don't let the re-login consume the general retry budget
                continue
            }

            # Timeout or transient - back off and retry
            if ($statusCode -in @(408, 429, 500, 502, 503, 504) -or $isTimeout) {
                $backoff = [Math]::Pow(2, $attempt)
                LogMessage("WARN: Status=$statusCode Timeout=$isTimeout on user $UserId ($UserName) attempt $attempt - backing off ${backoff}s")
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
    'Cleanup'
    'New-Login'
    'Get-AllUsers'
    'Get-UserDetails'
) -Variable @(
    'CybLegacyConfigurationModulePath'
    'CybADConfigurationModuleName'
    'CybSafeScanLogPath'
    'CybPVWAEndpointSuffixes'
    'CybUserInformationExcludedGroupPatterns'
    'CybUserGroupAssignmentConfig'
    'CybHumanUserScanConfig'
)
