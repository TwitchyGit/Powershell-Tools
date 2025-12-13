<#
.SYNOPSIS
    Runfile for CyberArk Account Reporting - report on objects, users and safes.

.DESCRIPTION
    This script connects to the CyberArk PVWA (Password Vault Web Access) API to generate
    comprehensive reports on accounts, users, and safes stored in the CyberArk vault.

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

# @FUNCTION@ ========================================================================================================
# Name..........: Invoke-PVWARestMethod
# Description...: Wrapper for REST API calls with comprehensive retry logic and error handling
#                 This function wraps PowerShell's Invoke-WebRequest to provide:
#                 - Exponential Backoff: Retries with increasing delays (5s, 10s, 20s)
#                 - Connection Timeout: Configurable timeout for slow networks
#                 - Auto Re-authentication: Detects 401 errors and re-authenticates automatically
#                 - Retryable Errors: Handles server errors (500, 502, 503, 504) and timeouts (408, 429)
#                 - Network Issues: Retries on timeout/connection errors
#                 - Graceful Degradation: Returns null on failure to allow continued processing
#                 - JSON Validation: Ensures response is valid JSON before returning
# Parameters....: 
#   - Uri: Full URL for the REST API endpoint
#   - Method: HTTP method (GET, POST, etc.)
#   - Headers: HTTP headers including authentication token
#   - Body: Request body for POST/PUT requests (JSON string)
#   - TimeoutSec: Request timeout in seconds
#   - MaxRetries: Maximum number of retry attempts
#   - RetryDelay: Initial delay in seconds (doubled on each retry)
# Return Values.: 
#   - Success: Response content as string (typically JSON)
#   - Failure: $null (error logged)
# =================================================================================================================
function Invoke-PVWARestMethod {
    [CmdletBinding()]
    param(
        [string]$Uri,
        [string]$Method = "GET",
        [hashtable]$Headers = @{},
        [string]$Body = $null,
        [int]$TimeoutSec = 300,
        [int]$MaxRetries = 3,
        [int]$RetryDelay = 5
    )

    $attempt = 0
    $success = $false
    $response = $null

    # Retry loop: Continue attempting until success or max retries reached
    while (-not $success -and $attempt -lt $MaxRetries) {
        $attempt++

        try {
            LogDebug "Attempt $attempt of $MaxRetries for: $Uri"

            # Build request parameters
            $requestParams = @{
                Uri                = $Uri
                Method             = $Method
                Headers            = $Headers
                ContentType        = "application/json"
                TimeoutSec         = $TimeoutSec
                UseBasicParsing    = $true              # Don't parse HTML (faster for JSON APIs)
            }

            # Add body for POST/PUT requests
            if ($Body) {
                $requestParams.Body = $Body
            }

            # Execute the HTTP request
            $response = Invoke-WebRequest @requestParams
            $success = $true

            # Validate HTTP status code is in success range (200-299)
            if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 300) {
                LogError "Received HTTP error status: $($response.StatusCode) from: $Uri"
                return $null
            }

            # Validate we received content in the response
            if ([string]::IsNullOrWhiteSpace($response.Content)) {
                LogError "Received empty response from: $Uri"
                return $null
            }

            $content = $response.Content

            # Validate response is valid JSON (CyberArk API always returns JSON)
            try {
                $checkJson = $content | ConvertFrom-Json -ErrorAction Stop
                # If we get here, it's valid JSON - continue
            } catch {
                # FIXED: Safe string truncation - check for null before substring
                $contentPreview = if ($content) { 
                    $content.Substring(0, [Math]::Min(200, $content.Length)) 
                } else { 
                    "(null)" 
                }
                LogError "Received invalid JSON response from: $Uri. Content: $contentPreview"
                return $null
            }

            # Log detailed response information when debugging
            if ($InDebug -and (Test-Path $ErrFile -IsValid)) {
                try {
                    New-Item $ErrFile -ItemType File -Force -ErrorAction SilentlyContinue
                    Add-Content -Path $ErrFile -Value "Raw Response: $content" -ErrorAction SilentlyContinue
                    Add-Content -Path $ErrFile -Value "Content Type: $($response.Headers['Content-Type'])" -ErrorAction SilentlyContinue
                    Add-Content -Path $ErrFile -Value "Status Code: $($response.StatusCode)" -ErrorAction SilentlyContinue
                } catch {
                    # Ignore errors during debug logging
                }
            }

            LogDebug "Successfully completed request to: $Uri"
            return $content

        } catch {
            # Extract error information from the exception
            $statusCode = $null
            $errorMessage = $_.Exception.Message
            $responseBody = $null

            # Try to get HTTP status code from the exception
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.Value__

                # Try to read the response body for detailed error messages
                try {
                    if ($_.Exception.Response.GetResponseStream) {
                        $streamReader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                        $responseBody = $streamReader.ReadToEnd()
                        $streamReader.Close()
                    }
                } catch {
                    # Ignore errors reading response body
                }
            }

            # Build comprehensive error message
            $errorDetails = "Status: $statusCode, Error: $errorMessage"
            if ($responseBody) {
                $errorDetails += ", Response: $responseBody"
            }

            LogError "Attempt $attempt failed for $Uri - $errorDetails"

            # Determine if this error should be retried
            # Retryable: Server errors (5xx), timeouts (408), rate limits (429)
            # Non-retryable: Client errors (4xx except 408, 429), authentication issues
            $retryableErrors = @(500, 502, 503, 504, 408, 429)  
            $isRetryable = $statusCode -in $retryableErrors -or $errorMessage -match "timeout|connection|network"

            # If we have retries left and the error is retryable, wait and retry
            if ($attempt -lt $MaxRetries -and $isRetryable) {
                # Exponential backoff: 5s, 10s, 20s, etc.
                $waitTime = $RetryDelay * [Math]::Pow(2, $attempt - 1)
                LogOutput "Retrying in $waitTime seconds..."
                Start-Sleep -Seconds $waitTime

                # FIXED: Handle authentication expiration (401 Unauthorized)
                # Update script-level token so all future calls use the new token
                if ($statusCode -eq 401) {
                    LogOutput "Authentication may have expired, attempting to re-authenticate..."
                    try {
                        $script:AuthTrimmed = Get-AuthToken
                        # Update the passed-in headers for this retry
                        $Headers['Authorization'] = $script:AuthTrimmed
                        LogOutput "Re-authentication successful, retrying request..."
                    } catch {
                        LogError "Re-authentication failed: $($_.Exception.Message)"
                        return $null
                    }
                }
            } else {
                # Max retries reached or non-retryable error
                LogError "Failed after $MaxRetries attempts: $errorDetails"
                return $null
            }
        }
    }

    # Should not reach here, but handle edge case
    LogError "All retry attempts exhausted for: $Uri"
    return $null
}

# @FUNCTION@ ========================================================================================================
# Name..........: Get-AuthToken
# Description...: Authenticate with CyberArk PVWA and retrieve session token
#                 This function:
#                 Loads encrypted credentials from XML file
#                 Decrypts the password
#                 Sends authentication request to PVWA
#                 Returns authentication token for subsequent API calls
#                 Securely disposes of credentials from memory
# Parameters....: n/a (uses script-level configuration variables)
# Return Values.: 
#   - Success: Authentication token (string)
#   - Failure: Exits script with error code 1
# =================================================================================================================
function Get-AuthToken {
    [CmdletBinding()]
    param()

    # Verify credential file exists before attempting to load
    if (-not (Test-Path $ConfAccountCredFile)) {
        LogError "Credential file not found: $ConfAccountCredFile"
        exit 1
    }

    # Load encrypted credentials (created with Get-Credential | Export-Clixml)
    LogDebug "Attempting to load credentials from: $ConfAccountCredFile"
    $PVWACreds = Import-Clixml -Path $ConfAccountCredFile

    # Validate credentials were loaded successfully
    if (-not $PVWACreds) {
        LogError "Failed to import credentials from $ConfAccountCredFile"
        exit 1
    }

    # Validate username is present
    if (-not $PVWACreds.UserName) {
        LogError "Username is empty in credential file $ConfAccountCredFile"
        exit 1
    }

    # Validate password is present
    if (-not $PVWACreds.Password) {
        LogError "Password is empty in credential file $ConfAccountCredFile"
        exit 1
    }

    # Build authentication request body
    # GetNetworkCredential().Password decrypts the secure string
    $AuthBody = @{
        "username" = $PVWACreds.UserName
        "password" = $PVWACreds.GetNetworkCredential().Password
    } | ConvertTo-Json

    LogDebug "Credentials loaded successfully for user: $($PVWACreds.UserName)"
    LogDebug "Authentication URL: $PVWALogonUrl"
    LogDebug "Sending authentication request..."

    # Clear PSCredential from memory for security
    if ($null -ne $PVWACreds) {
        $PVWACreds.Password.Dispose()
        $PVWACreds = $null
    }

    try {
        # Send authentication request to PVWA
        $authResponse = Invoke-PVWARestMethod -Uri $PVWALogonUrl -Method "POST" -Body $AuthBody -TimeoutSec $ConnectionTimeoutSeconds

        if ($authResponse) {
            # Remove quotes from token (API returns token wrapped in quotes)
            $authResponse = $authResponse -replace '"', ''
            LogDebug "Authentication successful, token length: $($authResponse.Length)"
            return $authResponse
        } else {
            LogError "Failed to authenticate with PVWA - no response received"
            exit 1
        }

    } catch {
        LogError "Failed to authenticate with PVWA: $($_.Exception.Message)"
        exit 1
    } finally {
        # Ensure credentials are cleared from memory even if error occurs
        if ($PVWACreds) {
            $PVWACreds.Password.Dispose()
            $PVWACreds = $null
        }
    }
}

# @FUNCTION@ ========================================================================================================
# Name..........: Get-AllSafes
# Description...: Retrieve all safes from CyberArk vault with pagination
#                 CyberArk returns safes in pages (default 100 per page). This function:
#                 Requests first page of safes
#                 Continues requesting subsequent pages until no more data
#                 Accumulates all safes into a single array
#                 Returns complete list of all safes
# Parameters....: n/a (uses script-level configuration)
# Return Values.: Array of safe objects (each containing safe name, permissions, settings, etc.)
# =================================================================================================================
function Get-AllSafes {
    [CmdletBinding()]
    param()

    $allSafes = @()           # Array to accumulate all safes
    $offset = 0               # Starting position (0 = first record)
    $limit = 100              # Records per page (100 is API default)
    $moreSafes = $true        # Flag to control pagination loop
    $seenIds = @{}            # FIXED: Track unique IDs to detect duplicate pagination

    LogOutput "Retrieving all safes..."

    # Continue looping until we've retrieved all safes
    while ($moreSafes) {
        try {
            # Build API URL with pagination parameters
            # offset: starting record number
            # limit: maximum records to return
            $uri = "${PVWAGetSafesUrl}?offset=$offset&limit=$limit"

            LogDebug "Requesting safes from: $uri"
            
            # Make API call with authentication header
            $response = Invoke-PVWARestMethod -Uri $uri -Headers @{'Authorization' = $script:AuthTrimmed } -TimeoutSec $ConnectionTimeoutSeconds

            # FIXED: Validate we received a response before proceeding
            if ([string]::IsNullOrWhiteSpace($response)) {
                LogError "Received null or empty response for safes at offset $offset"
                throw "Failed to retrieve safes - API returned no data"
            }

            # Parse JSON response
            try {
                $safesData = $response | ConvertFrom-Json -ErrorAction Stop
            } catch {
                # FIXED: Safe string truncation
                $responsePreview = if ($response) { 
                    $response.Substring(0, [Math]::Min(200, $response.Length)) 
                } else { 
                    "(null)" 
                }
                LogError "Failed to parse safes JSON response at offset $offset. Error: $($_.Exception.Message). Response preview: $responsePreview"
                throw "Failed to parse safes response"
            }

            # Check if we received safe data in this page
            if ($safesData -and $safesData.value -and $safesData.value.Count -gt 0) {
                # FIXED: Detect duplicate safes (pagination issue detection)
                $duplicatesFound = $false
                foreach ($safe in $safesData.value) {
                    if ($seenIds.ContainsKey($safe.safeName)) {
                        LogError "Duplicate safe detected: $($safe.safeName) at offset $offset - pagination may be broken"
                        $duplicatesFound = $true
                        break
                    }
                    $seenIds[$safe.safeName] = $true
                }
                
                if ($duplicatesFound) {
                    LogError "Stopping safe retrieval due to duplicate detection"
                    break
                }
                
                # Add this page of safes to our collection
                $allSafes += $safesData.value
                
                # Move to next page
                $offset += $limit
                
                LogOutput "Retrieved $($safesData.value.Count) safes (offset: $offset, total so far: $($allSafes.Count))"

                # Show progress indicator (unless running in Autosys scheduler)
                if (-not $isAutosys) {
                    Write-Progress -Activity "Retrieving Safes" -Status "$($allSafes.Count) safes retrieved so far" -PercentComplete -1
                }
            } else {
                # No more safes to retrieve
                LogOutput "No more safes found at offset $offset"
                $moreSafes = $false
            }

        } catch {
            LogError "Failed to retrieve safes at offset $offset : $($_.Exception.Message)"
            $moreSafes = $false
        }
    }

    LogOutput "Retrieved $($allSafes.Count) safes total"
    return $allSafes
}


# @FUNCTION@ ========================================================================================================
# Name..........: Get-Users
# Description...: Retrieve all users from CyberArk vault with extended details
#                 This function retrieves complete user information including:
#                 - User IDs and usernames
#                 - User types (CyberArk, LDAP, RADIUS, etc.)
#                 - Group memberships
#                 - Vault authorization levels
#                 - Suspended status
# Parameters....: n/a (uses script-level configuration)
# Return Values.: 
#   - Success: User data object containing array of users
#   - Failure: Throws exception
# =================================================================================================================
function Get-Users {
    [CmdletBinding()]
    param()

    try {
        # Make API call to retrieve users with extended details
        # ExtendedDetails=true includes group memberships and permissions
        $response = Invoke-PVWARestMethod -Uri $PVWAGetUsersUrl -Headers @{'Authorization' = $script:AuthTrimmed } -TimeoutSec $ConnectionTimeoutSeconds

        # FIXED: Validate response before parsing
        if ([string]::IsNullOrWhiteSpace($response)) {
            throw "Failed to retrieve users - API returned no data"
        }

        # Validate and parse JSON response
        try {
            return $response | ConvertFrom-Json -ErrorAction Stop
        } catch {
            # FIXED: Safe string truncation
            $responsePreview = if ($response) { 
                $response.Substring(0, [Math]::Min(200, $response.Length)) 
            } else { 
                "(null)" 
            }
            throw "Failed to parse users JSON response: $($_.Exception.Message). Response preview: $responsePreview"
        }

    } catch {
        throw "Failed to retrieve users: $($_.Exception.Message)"
    }
}

# @FUNCTION@ ========================================================================================================
# Name..........: Process-AccountsReport
# Description...: Generate comprehensive accounts report and export to CSV
#                 This function orchestrates the account reporting process:
#                 Calls Get-AllAccountsBulk-Streaming to retrieve all accounts
#                 Uses streaming approach to handle large datasets (100k+ accounts)
#                 Writes directly to CSV file to minimize memory usage
#                 Returns total count of accounts processed
# Parameters....: n/a (uses script-level configuration)
# Return Values.: n/a (writes report to file)
# =================================================================================================================
function Process-AccountsReport {
    [CmdletBinding()]
    param()

    try {
        LogOutput "Starting accounts report generation..."
        
        # Define output file name and path
        $TargetFile = "Data_PasswordObjects_Bulk.csv"
        $OutputPath = "$ConfDirLogs\$TargetFile"

        # FIXED: Validate output directory exists and is writable before starting long operation
        $outputDirectory = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDirectory)) {
            throw "Output directory does not exist: $outputDirectory"
        }

        # Test write access to output file
        try {
            Set-Content -Path $OutputPath -Value "# Test write access" -ErrorAction Stop
            Remove-Item -Path $OutputPath -ErrorAction SilentlyContinue
        } catch {
            throw "Cannot write to output file: $OutputPath. Error: $($_.Exception.Message)"
        }

        # Use streaming approach to avoid memory issues with large datasets
        # PageSize of 1000 balances API performance with memory usage
        $totalAccounts = Get-AllAccountsBulk-Streaming -PageSize 1000 -OutputPath $OutputPath

        LogOutput "Large-scale Account Report completed: $totalAccounts accounts written to $OutputPath"

    } catch {
        LogError "Large-scale script execution failed: $($_.Exception.Message)"
        throw
    }
}

# @FUNCTION@ ========================================================================================================
# Name..........: Get-AllAccountsBulk-Streaming
# Description...: Retrieve all accounts with streaming to file for memory efficiency
#                 This function handles large-scale account retrieval (100k+ accounts):
#                 Retrieves accounts in pages (default 1000 per page)
#                 Processes each batch immediately
#                 Streams results directly to CSV file (or returns array if no file specified)
#                 Performs garbage collection every 50k accounts
#                 Shows progress updates
#                 Memory-efficient approach for large datasets by:
#                 - Not storing all accounts in memory
#                 - Writing to file incrementally
#                 - Regular garbage collection
# Parameters....: 
#   - PageSize: Number of accounts to retrieve per API call (default: 1000)
#   - OutputPath: Optional file path to stream results (if null, returns array)
# Return Values.: 
#   - If OutputPath provided: Total count of accounts processed
#   - If no OutputPath: Array of all accounts
# =================================================================================================================
function Get-AllAccountsBulk-Streaming {
    [CmdletBinding()]
    param(
        [int]$PageSize = 1000,
        [string]$OutputPath = $null
    )

    $totalAccounts = 0                                          # Running count of total accounts
    $offset = 0                                                 # Starting position for pagination
    $moreAccounts = $true                                       # Flag to control pagination loop
    $processedAccounts = [System.Collections.ArrayList]::new()  # Array list for non-streaming mode
    $seenIds = @{}                                              # FIXED: Track unique IDs to detect duplicate pagination
    $scriptStart = Get-Date                                     # FIXED: Track script start time for timeout
    $maxScriptDuration = 12                                     # FIXED: Maximum runtime in hours

    LogOutput "Starting streaming bulk retrieval of accounts..."

    # If streaming to file, write CSV header first
    if ($OutputPath) {
        # Define all CSV columns
        $csvHeader = '"rowid","AccountName","Address","UserName","Platform","ModificationDate","ModifiedBy","LastUsedDate",`
            "LastUsedBy","Safe","CreatedBy","CreationDate","CPMStatus","Folder","LastTask","CPMErrorDetails","CPMDisabled",`
            "LastFailDate","LastSuccessVerification","DateTimeNow","ResetImmediately","ApplicationID","ConfigItemType",`
            "LastReconciledTime","PlatformAccountProperties"'
        Set-Content -Path $OutputPath -Value $csvHeader -Encoding UTF8
    }

    # Continue looping until we've retrieved all accounts
    while ($moreAccounts) {
        # FIXED: Check for overall script timeout
        if ((Get-Date) -gt $scriptStart.AddHours($maxScriptDuration)) {
            LogError "Script exceeded maximum runtime of $maxScriptDuration hours at offset $offset"
            throw "Script timeout - may indicate pagination loop issue"
        }

        try {
            # Build API URL with pagination parameters
            $uri = "${PVWAAccountsUrl}?offset=$offset&limit=$PageSize"
            LogDebug "Requesting accounts from: $uri (offset: $offset)"

            # Make API call with authentication header
            $response = Invoke-PVWARestMethod -Uri $uri -Headers @{'Authorization' = $script:AuthTrimmed } -TimeoutSec $ConnectionTimeoutSeconds

            # FIXED: Validate we received a response before proceeding
            if ([string]::IsNullOrWhiteSpace($response)) {
                LogError "Received null or empty response for accounts at offset $offset"
                throw "Failed to retrieve accounts - API returned no data at offset $offset"
            }

            # Parse JSON response
            try {
                $accountsData = $response | ConvertFrom-Json -ErrorAction Stop
            } catch {
                LogError "Failed to parse accounts JSON response at offset $offset. Error: $($_.Exception.Message)"
                throw "Failed to parse accounts response"
            }

            # Check if we received account data in this batch
            if ($accountsData.value -and $accountsData.value.Count -gt 0) {
                # FIXED: Detect duplicate accounts (pagination issue detection)
                $duplicatesFound = $false
                foreach ($account in $accountsData.value) {
                    if ($seenIds.ContainsKey($account.id)) {
                        LogError "Duplicate account ID detected: $($account.id) at offset $offset - pagination may be broken"
                        $duplicatesFound = $true
                        break
                    }
                    $seenIds[$account.id] = $true
                }
                
                if ($duplicatesFound) {
                    LogError "Stopping account retrieval due to duplicate detection"
                    break
                }

                $batchCount = $accountsData.value.Count
                $totalAccounts += $batchCount

                LogOutput "Processing batch: $batchCount accounts (offset: $offset, total processed: $totalAccounts)"

                if ($OutputPath) {
                    # Stream directly to file to save memory
                    Process-AccountBatch-ToFile -Accounts $accountsData.value -OutputPath $OutputPath
                } else {
                    # Process and add to in-memory collection
                    $processedBatch = Process-AccountBatch -Accounts $accountsData.value
                    $null = $processedAccounts.AddRange($processedBatch)
                }

                # Move to next page
                $offset += $PageSize

                # Show progress indicator (unless running in Autosys scheduler)
                if (-not $isAutosys) {
                    Write-Progress -Activity "Retrieving Accounts" -Status "$totalAccounts accounts processed so far" -PercentComplete -1
                }

                # FIXED: Perform garbage collection every 50k accounts AND at the end
                if ($totalAccounts % 50000 -eq 0) {
                    LogOutput "Processed $totalAccounts accounts, performing garbage collection..."
                    [System.GC]::Collect()
                    [System.GC]::WaitForPendingFinalizers()
                }

                # Check if we got fewer results than requested (end of data)
                if ($batchCount -lt $PageSize) {
                    $moreAccounts = $false
                }
            } else {
                # No more accounts to retrieve
                LogOutput "No more accounts found at offset $offset"
                $moreAccounts = $false
            }
        } catch {
            LogError "Failed to retrieve accounts at offset $offset : $($_.Exception.Message)"
            # FIXED: Don't try to continue after failure - could cause data loss
            throw "Account retrieval failed - stopping to prevent incomplete report"
        }
    }

    # FIXED: Final garbage collection after streaming completes
    LogOutput "Performing final garbage collection..."
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    # Clear progress indicator
    if (-not $isAutosys) {
        Write-Progress -Activity "Retrieving Accounts" -Completed
    }

    LogOutput "Completed bulk retrieval: $totalAccounts accounts total"

    # Return appropriate result based on mode
    if ($OutputPath) {
        return $totalAccounts  # Return count when streaming to file
    } else {
        return $processedAccounts.ToArray()  # Return array of accounts
    }
}

# @FUNCTION@ ========================================================================================================
# Name..........: Process-AccountBatch
# Description...: Process a batch of accounts and add computed properties
#                 This function enriches account objects with additional properties:
#                 - Extracts secret management properties (status, last modified, etc.)
#                 - Extracts platform-specific properties (ApplicationID, ConfigItemType)
#                 - Prepares accounts for in-memory storage or export
# Parameters....: 
#   - Accounts: Array of account objects from API
# Return Values.: Array of processed account objects with additional properties
# =================================================================================================================
function Process-AccountBatch {
    param([array]$Accounts)

    # Pre-allocate array list for better performance
    $processedBatch = [System.Collections.ArrayList]::new($Accounts.Count)

    foreach ($Account in $Accounts) {
        if ($null -ne $Account) {
            # Add flattened properties from nested objects for easier CSV export
            # These properties are commonly used in reports and analysis
            
            # Secret management properties
            $Account | Add-Member -NotePropertyName isAutomaticManagementEnabled -NotePropertyValue $Account.secretManagement.automaticManagementEnabled -Force
            $Account | Add-Member -NotePropertyName manualManagement             -NotePropertyValue $Account.secretManagement.manualManagementReason -Force
            $Account | Add-Member -NotePropertyName status                       -NotePropertyValue $Account.secretManagement.status -Force
            $Account | Add-Member -NotePropertyName lastModifiedTime             -NotePropertyValue $Account.secretManagement.lastModifiedTime -Force
            $Account | Add-Member -NotePropertyName lastReconciledTime           -NotePropertyValue $Account.secretManagement.lastReconciledTime -Force
            $Account | Add-Member -NotePropertyName lastVerifiedTime             -NotePropertyValue $Account.secretManagement.lastVerifiedTime -Force
            
            # Platform-specific properties
            $Account | Add-Member -NotePropertyName PlatformAccountID            -NotePropertyValue $Account.platformAccountProperties.ApplicationID -Force
            $Account | Add-Member -NotePropertyName ConfigItemType               -NotePropertyValue $Account.platformAccountProperties.ConfigItemType -Force

            $null = $processedBatch.Add($Account)
        }
    }

    return $processedBatch.ToArray()
}

# @FUNCTION@ ========================================================================================================
# Name..........: Process-AccountBatch-ToFile
# Description...: Process a batch of accounts and write directly to CSV file
#                 This function is used for streaming large datasets:
#                 Processes each account in the batch
#                 Adds computed properties (same as Process-AccountBatch)
#                 Formats account data as CSV lines
#                 Appends lines directly to file (doesn't store in memory)
#                 Memory-efficient for large datasets (100k+ accounts)
# Parameters....: 
#   - Accounts: Array of account objects from API
#   - OutputPath: File path to append CSV lines
# Return Values.: n/a (writes to file)
# =================================================================================================================
function Process-AccountBatch-ToFile {
    param(
        [array]$Accounts,
        [string]$OutputPath
    )

    # Pre-allocate array list for CSV lines
    $csvLines = [System.Collections.ArrayList]::new($Accounts.Count)

    foreach ($Account in $Accounts) {
        if ($null -ne $Account) {
            # Add flattened properties from nested objects
            # (Same enrichment as Process-AccountBatch function)
            
            # Secret management properties
            $Account | Add-Member -NotePropertyName isAutomaticManagementEnabled -NotePropertyValue $Account.secretManagement.automaticManagementEnabled -Force
            $Account | Add-Member -NotePropertyName manualManagement             -NotePropertyValue $Account.secretManagement.manualManagementReason -Force
            $Account | Add-Member -NotePropertyName status                       -NotePropertyValue $Account.secretManagement.status -Force
            $Account | Add-Member -NotePropertyName lastModifiedTime             -NotePropertyValue $Account.secretManagement.lastModifiedTime -Force
            $Account | Add-Member -NotePropertyName lastReconciledTime           -NotePropertyValue $Account.secretManagement.lastReconciledTime -Force
            $Account | Add-Member -NotePropertyName lastVerifiedTime             -NotePropertyValue $Account.secretManagement.lastVerifiedTime -Force
            
            # Platform-specific properties
            $Account | Add-Member -NotePropertyName ApplicationID                -NotePropertyValue $Account.platformAccountProperties.ApplicationID -Force
            $Account | Add-Member -NotePropertyName ConfigItemType               -NotePropertyValue $Account.platformAccountProperties.ConfigItemType -Force

            # FIXED: Use proper CSV escaping via PowerShell objects instead of manual formatting
            # This properly handles special characters like commas, quotes, and newlines
            $csvObject = [PSCustomObject]@{
                rowid                      = $Account.id
                AccountName                = $Account.name
                Address                    = if ([string]::IsNullOrEmpty($Account.Address)) { ' ' } else { $Account.Address }
                UserName                   = if ([string]::IsNullOrEmpty($Account.UserName)) { ' ' } else { $Account.UserName }
                Platform                   = if ([string]::IsNullOrEmpty($Account.PlatformId)) { ' ' } else { $Account.PlatformId }
                ModificationDate           = (ConvertDate $Account.lastModifiedTime).Date
                ModifiedBy                 = '  '
                LastUsedDate               = '  '
                LastUsedBy                 = '  '
                Safe                       = if ([string]::IsNullOrEmpty($Account.Safename)) { 'SAFE' } else { $Account.Safename }
                CreatedBy                  = '  '
                CreationDate               = (ConvertDate $Account.createdTime).Date
                CPMStatus                  = if ([string]::IsNullOrEmpty($Account.status)) { 'NotSet' } else { $Account.status }
                Folder                     = '  '
                LastTask                   = '  '
                CPMErrorDetails            = if ([string]::IsNullOrEmpty($Account.reasonForManualManagement)) { 'NotSet' } else { $Account.reasonForManualManagement }
                CPMDisabled                = if ([string]::IsNullOrEmpty($Account.isAutomaticManagementEnabled)) { 'NotSet' } else { $Account.isAutomaticManagementEnabled }
                LastFailDate               = '  '
                LastSuccessVerification    = (ConvertDate $Account.lastVerifiedTime).Date
                DateTimeNow                = '  '
                ResetImmediately           = '  '
                ApplicationID              = if ([string]::IsNullOrEmpty($Account.ApplicationID)) { 'NotSet' } else { $Account.ApplicationID }
                ConfigItemType             = if ([string]::IsNullOrEmpty($Account.ConfigItemType)) { 'NotSet' } else { $Account.ConfigItemType }
                LastReconciledTime         = (ConvertDate $Account.lastReconciledTime).Date
                PlatformAccountProperties  = '  '
            }

            # Convert to CSV line (PowerShell handles escaping properly)
            $csvLine = ($csvObject | ConvertTo-Csv -NoTypeInformation)[1]  # [1] to skip header
            $null = $csvLines.Add($csvLine)
        }
    }

    # Append entire batch to file at once (more efficient than line-by-line)
    if ($csvLines.Count -gt 0) {
        Add-Content -Path $OutputPath -Value $csvLines -Encoding UTF8
    }
}

# @FUNCTION@ ========================================================================================================
# Name..........: Process-UsersReport
# Description...: Generate comprehensive users report and export to CSV
#                 FIXED: Now creates TWO separate CSV files instead of overwriting:
#                 1. Users with group memberships (semicolon-separated)
#                 2. User details with permissions and status
# Parameters....: n/a (uses script-level configuration)
# Return Values.: n/a (writes reports to files)
# =================================================================================================================
function Process-UsersReport {
    [CmdletBinding()]
    param()

    try {
        LogOutput "Starting users report generation..."

        # Define output file names - FIXED: Two separate files
        $TargetFileDetails = "Data_UserList_Details.csv"
        $TargetFileGroups = "Data_UserList_GroupMemberships.csv"

        # Retrieve all users from CyberArk with extended details
        $GetUsersResponse = Get-Users

        if ($GetUsersResponse -and $GetUsersResponse.Users) {
            # FIXED: First export - Users with their group memberships (separate file)
            # GroupMembership column contains semicolon-separated list of all groups
            $GetUsersResponse.Users | Select-Object -Property id, username, 
                @{Name = "GroupMembership"; Expression = { ($_.groupsMembership.groupName -join ';') }},
                source, userType, suspended |
                Export-Csv -Path "$ConfDirLogs\$TargetFileGroups" -NoTypeInformation -UseCulture -Force

            LogOutput "Users Group Memberships Report written to $ConfDirLogs\$TargetFileGroups"

            # Convert vaultAuthorization from Object[] to String for better CSV formatting
            # This ensures permissions are displayed clearly in the CSV
            foreach ($User in $GetUsersResponse.Users) {
                $User.vaultAuthorization = [String]$User.vaultAuthorization
            }

            # FIXED: Second export - Detailed user information (separate file, doesn't overwrite)
            # Includes: username, ID, authentication source, user type, permissions, suspended status
            $GetUsersResponse.Users | Select-Object -Property username, id, source, userType, vaultAuthorization, suspended |
                Export-Csv -Path "$ConfDirLogs\$TargetFileDetails" -NoTypeInformation -UseCulture -Force

            LogOutput "Users Details Report written to $ConfDirLogs\$TargetFileDetails"
        } else {
            LogError "Failed to retrieve users data"
            throw "No users data retrieved from API"
        }

    } catch {
        LogError "Users report generation failed: $($_.Exception.Message)"
        throw
    }
}

# @FUNCTION@ ========================================================================================================
# Name..........: Process-SafesReport
# Description...: Generate comprehensive safes report and export to CSV
#                 This function:
#                 Retrieves all safes from CyberArk
#                 Extracts key safe properties and settings
#                 Formats dates for readability
#                 Exports to CSV with retention policies and metadata
# Parameters....: n/a (uses script-level configuration)
# Return Values.: n/a (writes report to file)
# =================================================================================================================
function Process-SafesReport {
    [CmdletBinding()]
    param()

    try {
        LogOutput "Starting safes report generation..."

        # Define output file name and path
        $TargetFile = "Data_SafeDetails_Expanded.csv"

        # Retrieve all safes from CyberArk vault
        $allSafes = Get-AllSafes

        if ($allSafes -and $allSafes.Count -gt 0) {
            # Export safe details with selected properties
            # Includes: member info, metadata, retention settings, CPM configuration
            $allSafes | Select-Object -Property SafeMember, SafeName, Description, Location, `
                @{Name = "CreatedBy"; Expression = { $_.Creator.name } },                          # Extract creator name from nested object
                    olaEnabled,                                                                     # Object Level Access flag
                    ManagingCPM,                                                                    # CPM managing this safe
                    NumberOfDaysRetention,                                                          # Password retention (days)
                    NumberOfVersionsRetention,                                                      # Password retention (versions)
                    AutoPurgeEnabled,                                                               # Auto-delete old versions flag
                @{Name = 'creationTime'; Expression = { (ConvertDate $_.creationTime).Date } },    # Format creation date
                @{Name = 'lastModificationTime2'; Expression = { (ConvertDate $_.lastModificationTime).Date } },  # Format last modified date
                isExpiredMember |                                                                   # Member expiration status
                Export-Csv -Path $ConfDirLogs\$TargetFile -NoTypeInformation -UseCulture -Force

            LogOutput "Safes Report written to $ConfDirLogs\$TargetFile"
        } else {
            LogError "Failed to retrieve safes data or no safes found"
            throw "No safes data available"
        }

    } catch {
        LogError "Safes report generation failed: $($_.Exception.Message)"
        throw
    }
}

# @FUNCTION@ ========================================================================================================
# Name..........: Cleanup
# Description...: Perform garbage collection to free memory
#                 This function forces .NET garbage collection to:
#                 - Release memory used by large datasets
#                 - Close file handles
#                 - Clean up temporary objects
#                 Important for scripts processing 100k+ records
# Parameters....: n/a
# Return Values.: n/a
# =================================================================================================================
function Cleanup {
    # Force immediate garbage collection
    [System.GC]::Collect()
    
    # Wait for finalizers to complete (ensures all objects are properly disposed)
    [System.GC]::WaitForPendingFinalizers()
}

# @MAIN@ ===========================================================================================================
# Main Script Body
# Load configuration and modules
# Initialize logging and working directory
# Build API endpoint URLs
# Authenticate with CyberArk PVWA
# Generate requested reports (accounts, users, safes)
# Cleanup and exit
# =================================================================================================================

# Initialize exit code (0 = success, 1 = failure)
$exitCode = 0

# Define module directory path
# Contains shared configuration and utility functions
$Script:ModDir = "C:\Scripts\Config"

try {
    # Import required PowerShell modules
    # Configuration.psm1 contains shared functions for logging, config, ConvertDate, etc.
    Import-Module "$ModDir\Configuration.psm1" -Force -ErrorAction Stop
} catch {
    Write-Output "ERROR: Unable to import modules: $($_.Exception.Message)"
    exit 1
}

# Set script preferences based on command-line parameters
$InDebug = $PSBoundParameters.Debug.IsPresent          # Enable debug logging if -Debug specified
$InVerbose = $PSBoundParameters.Verbose.IsPresent      # Enable verbose logging if -Verbose specified
$isAutosys = [bool][Environment]::GetEnvironmentVariable('AUTO_JOB_NAME')  # Detect if running in Autosys scheduler

# Configure global preferences (affects Write-Progress, logging verbosity, etc.)
Set-GlobalPreferences -EnableVerbose:$InVerbose -EnableDebug:$InDebug -IsAutosys:$isAutosys

# Validate environment is configured
# Environment variable should be set by Configuration.psm1 (e.g., DEV, TEST, PROD)
if (-not $Environment -and $null -eq $Environment) {
    LogError "Environment variable must be set via $ModDir\Configuration.psm1"
    exit 1
}

# Initialize logging system
# Creates log file and begins logging session
$Script:LogPath = "D:\Logs\Scan-AllObjectsInSafes.log"
LogStartScript

# Set working directory for script execution
# ConfDirFiles should be defined in Configuration.psm1
Set-Location $ConfDirFiles

# Build CyberArk API endpoint URLs
# All CyberArk REST API calls use these base endpoints

# API endpoint suffixes (relative paths)
$PVWAAuthSuffix = "API/auth/Cyberark/Logon/"           # Authentication endpoint
$PVWAGetAccountsSuffix = "API/Accounts/"               # Accounts retrieval endpoint
$PVWAGetUsersSuffix = "API/Users?ExtendedDetails=true" # Users retrieval with extended details
$PVWAGetSafesSuffix = "API/Safes/"                     # Safes retrieval endpoint

# Build complete URLs by combining base PVWA URL with suffixes
$PVWALogonUrl = $ConfPVWAURL + $PVWAAuthSuffix
$PVWAAccountsUrl = $ConfPVWAURL + $PVWAGetAccountsSuffix
$PVWAGetUsersUrl = $ConfPVWAURL + $PVWAGetUsersSuffix
$PVWAGetSafesUrl = $ConfPVWAURL + $PVWAGetSafesSuffix

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

# ===== AUTHENTICATION =====
# Authenticate with CyberArk PVWA to obtain session token
# Token is stored in $script:AuthTrimmed and used for all subsequent API calls
try {
    LogOutput "Authenticating with PVWA..."
    $script:AuthTrimmed = Get-AuthToken
    LogOutput "Authentication successful"
} catch {
    LogError "Authentication failed: $($_.Exception.Message)"
    exit 1
}

# ===== REPORT GENERATION =====
# FIXED: Standardized error handling - all reports use same pattern
# Generate requested reports based on command-line switches
# Each report runs independently - failures are logged but don't stop other reports

# Generate Accounts Report if requested
if ($ReportAccounts) {
    try {
        Process-AccountsReport
    } catch {
        LogError "Accounts report failed: $($_.Exception.Message)"
        $exitCode = 1  # Mark script as failed but continue with other reports
    }
}

# Generate Users Report if requested
if ($ReportUsers) {
    try {
        Process-UsersReport
    } catch {
        LogError "Users report failed: $($_.Exception.Message)"
        $exitCode = 1  # Mark script as failed but continue with other reports
    }
}

# Generate Safes Report if requested
if ($ReportSafes) {
    try {
        Process-SafesReport
    } catch {
        LogError "Safes report failed: $($_.Exception.Message)"
        $exitCode = 1  # Mark script as failed but continue
    }
}

# ===== CLEANUP AND EXIT =====
# Perform cleanup operations and exit with appropriate code

# Free memory and close file handles
Cleanup

# Log completion message
LogOutput "Script execution completed with exit code: $exitCode"

# Exit with status code (0 = success, 1 = one or more reports failed)
exit $exitCode
