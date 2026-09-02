$configurationModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'ConfigModule.psm1'

if (-not (Test-Path -LiteralPath $configurationModulePath -PathType Leaf)) {
    throw "Configuration module not found: $configurationModulePath"
}

Import-Module -Name $configurationModulePath -Force -Scope Local -ErrorAction Stop

function Initialize-CybOnboardingContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Configuration
    )

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

  # try direct identity first
  try {
    $g = Get-ADGroup @common -Identity $Group -Properties distinguishedName
    if ($g -and $g.DistinguishedName) { return $g.DistinguishedName }
  } catch { }

  # fallback: search by samAccountName or CN under domain naming context
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

    while ($attempt -lt $MaxRetries) {
        $attempt++
        
        try {
            LogDebug "Attempt $attempt of $MaxRetries for: $Uri"

            $requestParams = @{
                Uri             = $Uri
                Method          = $Method
                Headers         = $Headers
                ContentType     = "application/json"
                TimeoutSec      = $TimeoutSec
                UseBasicParsing = $true
            }

            if ($Body) { $requestParams.Body = $Body }

            # Force connection closure to prevent connection pool issues
            if (-not $requestParams.Headers) {
                $requestParams.Headers = @{}
            }
            $requestParams.Headers['Connection'] = 'close'

            $response = Invoke-WebRequest @requestParams
            
            # Success - return content
            return $response.Content

        } catch {
            # Extract status code safely
            $statusCode = $null
            $errorMessage = $_.Exception.Message
            
            if ($_.Exception.Response) {
                try {
                    $statusCode = [int]$_.Exception.Response.StatusCode
                } catch {
                    # Status code not available
                }
            }

            LogError "Attempt $attempt failed for $Uri - Status: $statusCode, Error: $errorMessage"

            # Determine if we should retry
            $shouldRetry = $false
            
            if ($attempt -lt $MaxRetries) {
                # Retry on: network errors, rate limits, temporary server errors, connection errors
                # Don't retry on: client errors (except 429), or persistent 500 errors
                $networkError = $errorMessage -match "timeout|connection|network|underlying connection|send|closed"
                $retryableStatus = $statusCode -in @(429, 502, 503, 504)
                $firstTime500 = ($statusCode -eq 500) -and ($attempt -eq 1)
                
                $shouldRetry = $networkError -or $retryableStatus -or $firstTime500
            }

            if ($shouldRetry) {
                $waitTime = $RetryDelay * [Math]::Pow(2, $attempt - 1)
                LogOutput "Retrying in $waitTime seconds..."
                Start-Sleep -Seconds $waitTime

                # Re-authenticate on 401
                if ($statusCode -eq 401) {
                    LogOutput "Re-authenticating..."
                    try {
                        $CybOnboardingRuntime.AuthTrimmed = Get-AuthToken
                        $Headers['Authorization'] = $CybOnboardingRuntime.AuthTrimmed
                    } catch {
                        LogError "Re-authentication failed: $($_.Exception.Message)"
                        return $null
                    }
                }
            } else {
                LogError "Non-retryable error or max retries reached"
                return $null
            }
        }
    }

    return $null
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
    $failureCount = 0
    $maxFailures = 3

    LogOutput "Retrieving all safes..."

    while ($failureCount -lt $maxFailures) {
        try {
            $uri = "${PVWAGetSafesUrl}?offset=$offset&limit=$limit"
            LogDebug "Requesting safes: $uri"

            $response = Invoke-PVWARestMethod `
                -Uri $uri `
                -Headers @{'Authorization' = $CybOnboardingRuntime.AuthTrimmed } `
                -TimeoutSec $CybOnboardingRuntime.ConnectionTimeoutSeconds

            if ([string]::IsNullOrWhiteSpace($response)) {
                LogOutput "No more safes at offset $offset"
                break
            }

            $safesData = $response | ConvertFrom-Json -ErrorAction Stop

            if ($safesData.value -and $safesData.value.Count -gt 0) {
                $allSafes += $safesData.value
                $offset += $limit
                $failureCount = 0
                
                LogOutput "Retrieved $($safesData.value.Count) safes (total: $($allSafes.Count))"
                
                if (-not $CybOnboardingRuntime.isAutosys) {
                    Write-Progress -Activity "Retrieving Safes" -Status "$($allSafes.Count) safes" -PercentComplete -1
                }
                
                # End if partial page
                if ($safesData.value.Count -lt $limit) { break }
            } else {
                break
            }

        } catch {
            LogError "Failed to retrieve safes at offset $offset : $($_.Exception.Message)"
            $failureCount++
            $offset += $limit
        }
    }

    LogOutput "Retrieved $($allSafes.Count) safes total"
    return $allSafes
}

function Get-Users {
    [CmdletBinding()]
    param()

    try {
        # Make API call to retrieve users with extended details
        # ExtendedDetails=true includes group memberships and permissions
        $response = Invoke-PVWARestMethod -Uri $CybOnboardingRuntime.PVWAGetUsersUrl -Headers @{'Authorization' = $CybOnboardingRuntime.AuthTrimmed } -TimeoutSec $CybOnboardingRuntime.ConnectionTimeoutSeconds

        # Validate response before parsing
        if ([string]::IsNullOrWhiteSpace($response)) {
            throw "Failed to retrieve users - API returned no data"
        }

        # Validate and parse JSON response
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

        # Define output file name and path
        $TargetFile = "Data_PasswordObjects_Bulk.csv"
        $OutputPath = Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFile

        # Validate output directory exists and is writable before starting long operation
        $outputDirectory = Split-Path $OutputPath -Parent
        if (-not (Test-Path $outputDirectory)) {
            throw "Output directory does not exist: $outputDirectory"
        }

        # Test write access to output file
        try {
            Set-Content -Path $OutputPath -Value "Test write access" -ErrorAction Stop
            Remove-Item -Path $OutputPath -ErrorAction SilentlyContinue
        } catch {
            throw "Cannot write to output file: $OutputPath. Error: $($_.Exception.Message)"
        }

        # Use streaming approach to avoid memory issues with large datasets
        # PageSize of 1000 balances API performance with memory usage
        # MaxThreads of 2 prevents connection pool exhaustion
        Get-AllAccounts -PageSize 1000 -OutputPath $OutputPath -MaxThreads 2
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
        [int]$PageSize = 1000,
        [string]$OutputPath = $null,
        [int]$MaxThreads = 2
    )

    $scriptStart = Get-Date
    $totalAccounts = 0
    $maxHours = 12

    LogOutput "Starting account retrieval (PageSize: $PageSize, Threads: $MaxThreads)"

    # Validate output path
    if (-not $OutputPath) {
        throw "OutputPath is required for account retrieval"
    }

    # Initialize CSV file
    $csvHeader = '"rowid","AccountName","Address","UserName","Platform","ModificationDate","ModifiedBy","LastUsedDate","LastUsedBy","Safe","CreatedBy","CreationDate","CPMStatus","Folder","LastTask","CPMErrorDetails","CPMDisabled","LastFailDate","LastSuccessVerification","DateTimeNow","ResetImmediately","ApplicationID","ConfigItemType","LastReconciledTime","PlatformAccountProperties"'
    Set-Content -Path $OutputPath -Value $csvHeader -Encoding UTF8

    # Retrieve all safes
    $allSafes = Get-AllSafes
    if (-not $allSafes -or $allSafes.Count -eq 0) {
        LogError "No safes retrieved - cannot enumerate accounts"
        $CybOnboardingRuntime.AccountsResult = 0
        return
    }

    $totalSafes = $allSafes.Count
    LogOutput "Retrieved $totalSafes safes - beginning account retrieval"

    # Shared state - thread-safe hashtable
    $sharedState = [hashtable]::Synchronized(@{
        AuthToken          = $CybOnboardingRuntime.AuthTrimmed
        PVWAAccountsUrl    = $CybOnboardingRuntime.PVWAAccountsUrl
        ConfPVWAURL        = $CybOnboardingRuntime.ConfPVWAURL
        LegacyConfigurationModulePath = $CybLegacyConfigurationModulePath
        TimeoutSeconds     = $CybOnboardingRuntime.ConnectionTimeoutSeconds
        PageSize           = $PageSize
        MaxRetries         = 10
        RetryDelaySeconds  = 3
    })

    $lastTokenRefresh = Get-Date

    # Scriptblock with HttpWebRequest for guaranteed connection control
    $scriptBlock = {
        param($SafeName, $SharedState)

        # Force TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Import ConvertDate function
        Import-Module -Name $SharedState.LegacyConfigurationModulePath -Force -ErrorAction SilentlyContinue

        $results = @{
            SafeName  = $SafeName
            CsvLines  = [System.Collections.ArrayList]::new()
            Count     = 0
            Error     = $null
        }

        # Helper function: Make HTTP request with guaranteed connection closure
        function Invoke-IsolatedWebRequest {
            param(
                [string]$Uri,
                [string]$AuthToken,
                [int]$TimeoutSeconds,
                [int]$MaxRetries
            )

            $attempt = 0
            while ($attempt -lt $MaxRetries) {
                $attempt++
                $request = $null
                $response = $null
                $responseStream = $null
                $reader = $null

                try {
                    # Create HttpWebRequest (lower-level than Invoke-WebRequest)
                    $request = [System.Net.HttpWebRequest]::Create($Uri)
                    $request.Method = "GET"
                    $request.ContentType = "application/json"
                    $request.Headers.Add("Authorization", $AuthToken)
                    $request.Timeout = $TimeoutSeconds * 1000
                    $request.ReadWriteTimeout = $TimeoutSeconds * 1000
                    
                    # CRITICAL: Force connection closure after each request
                    $request.KeepAlive = $false
                    $request.ProtocolVersion = [System.Net.HttpVersion]::Version11
                    $request.ServicePoint.ConnectionLimit = 1
                    $request.ServicePoint.Expect100Continue = $false
                    $request.ServicePoint.UseNagleAlgorithm = $false

                    # Get response
                    $response = $request.GetResponse()
                    $responseStream = $response.GetResponseStream()
                    $reader = [System.IO.StreamReader]::new($responseStream)
                    $content = $reader.ReadToEnd()

                    # Clean up immediately
                    if ($reader) { $reader.Close(); $reader.Dispose() }
                    if ($responseStream) { $responseStream.Close(); $responseStream.Dispose() }
                    if ($response) { $response.Close(); $response.Dispose() }

                    return $content

                } catch {
                    # Clean up on error
                    if ($reader) { try { $reader.Close(); $reader.Dispose() } catch {} }
                    if ($responseStream) { try { $responseStream.Close(); $responseStream.Dispose() } catch {} }
                    if ($response) { try { $response.Close(); $response.Dispose() } catch {} }

                    $statusCode = $null
                    if ($_.Exception.Response) {
                        try { $statusCode = [int]$_.Exception.Response.StatusCode } catch {}
                    }

                    # Retry on transient errors
                    if ($attempt -lt $MaxRetries) {
                        $isRetryable = $statusCode -in @(401, 429, 500, 502, 503, 504) -or 
                                       $_.Exception.Message -match "timeout|connection|closed|send|receive"
                        
                        if ($isRetryable) {
                            $waitSeconds = [Math]::Min(30, 2 * $attempt)
                            Start-Sleep -Seconds $waitSeconds
                            continue
                        }
                    }

                    throw
                }
            }

            throw "Failed after $MaxRetries attempts"
        }

        try {
            $encodedSafeName = [Uri]::EscapeDataString($SafeName)
            $uri = "$($SharedState.PVWAAccountsUrl)?filter=safeName eq ${encodedSafeName}&limit=$($SharedState.PageSize)"

            $pageCount = 0
            $maxPages = 1000

            while ($pageCount -lt $maxPages) {
                $pageCount++

                # Make request with guaranteed connection isolation
                $content = Invoke-IsolatedWebRequest `
                    -Uri $uri `
                    -AuthToken $SharedState.AuthToken `
                    -TimeoutSeconds $SharedState.TimeoutSeconds `
                    -MaxRetries $SharedState.MaxRetries

                if ([string]::IsNullOrWhiteSpace($content)) { break }

                $accountsData = $content | ConvertFrom-Json -ErrorAction Stop

                if (-not $accountsData -or -not $accountsData.value -or $accountsData.value.Count -eq 0) { break }

                # Process accounts into CSV rows
                foreach ($Account in $accountsData.value) {
                    if ($null -eq $Account) { continue }

                    $secretMgmt = $Account.secretManagement
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

                    [void]$results.CsvLines.Add($csvLine)
                    $results.Count++
                }

                # Check for next page
                if ($accountsData.nextLink) {
                    if ($accountsData.nextLink -match '^https?://') {
                        $uri = $accountsData.nextLink
                    } else {
                        $uri = $SharedState.ConfPVWAURL + "/" + $accountsData.nextLink.TrimStart("/")
                    }
                    Start-Sleep -Milliseconds 100
                } else {
                    break
                }
            }

        } catch {
            $results.Error = "Error processing safe: $($_.Exception.Message)"
        }

        return $results
    }

    # Create runspace pool with LIMITED concurrency
    $runspacePool = [RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
    $runspacePool.Open()

    $jobs = [System.Collections.ArrayList]::new()
    $excludedPatterns = @('CPM*', 'Log*', 'Notification*', 'Pictures', 'PSM*', 'PVWA*', 'System*', 'VaultInternal*')

    $safeIndex = 0
    $completedSafes = 0
    $queuedSafes = 0

    # Queue safes for processing
    foreach ($safe in $allSafes) {
        if ([string]::IsNullOrWhiteSpace($safe.safeName)) {
            $completedSafes++
            continue
        }

        # Skip excluded safes
        $skipSafe = $false
        foreach ($pattern in $excludedPatterns) {
            if ($safe.safeName -like $pattern) {
                $skipSafe = $true
                break
            }
        }
        if ($skipSafe) {
            $completedSafes++
            continue
        }

        $safeIndex++

        # Timeout check
        if ((Get-Date) -gt $scriptStart.AddHours($maxHours)) {
            LogError "Script exceeded $maxHours hour limit - stopping"
            break
        }

        # Create and queue job
        $ps = [PowerShell]::Create()
        $ps.RunspacePool = $runspacePool
        [void]$ps.AddScript($scriptBlock)
        [void]$ps.AddArgument($safe.safeName)
        [void]$ps.AddArgument($sharedState)

        $handle = $ps.BeginInvoke()

        [void]$jobs.Add(@{
            PowerShell = $ps
            Handle     = $handle
            SafeName   = $safe.safeName
            StartTime  = Get-Date
        })

        $queuedSafes++

        # Delay between job submissions to prevent connection storms
        Start-Sleep -Milliseconds 200

        # Collect completed jobs periodically
        if ($queuedSafes % 5 -eq 0 -or $safeIndex -eq $totalSafes) {

            # Refresh auth token every 15 minutes
            if ((Get-Date) -gt $lastTokenRefresh.AddMinutes(15)) {
                try {
                    LogOutput "Refreshing auth token..."
                    $CybOnboardingRuntime.AuthTrimmed = Get-AuthToken
                    $sharedState.AuthToken = $CybOnboardingRuntime.AuthTrimmed
                    $lastTokenRefresh = Get-Date
                    LogOutput "Token refreshed"
                } catch {
                    LogError "Token refresh failed: $($_.Exception.Message)"
                }
            }

            # Collect completed jobs
            $completedJobs = $jobs | Where-Object { $_.Handle.IsCompleted }

            foreach ($job in $completedJobs) {
                try {
                    $result = $job.PowerShell.EndInvoke($job.Handle)

                    if ($result -and $result.Count -gt 0) {
                        $safeResult = $result[0]

                        if ($safeResult.Error) {
                            LogError "Safe '$($safeResult.SafeName)': $($safeResult.Error)"
                        }

                        if ($safeResult.CsvLines -and $safeResult.CsvLines.Count -gt 0) {
                            Add-Content -Path $OutputPath -Value $safeResult.CsvLines -Encoding UTF8
                            $totalAccounts += $safeResult.Count
                        }
                    }

                    $completedSafes++

                } catch {
                    LogError "Error collecting result for '$($job.SafeName)': $($_.Exception.Message)"
                    $completedSafes++
                } finally {
                    $job.PowerShell.Dispose()
                }
            }

            # Remove completed jobs
            foreach ($cj in $completedJobs) {
                $jobs.Remove($cj)
            }

            # Progress
            if (-not $CybOnboardingRuntime.isAutosys -and $totalSafes -gt 0) {
                $pct = [Math]::Min(100, [int](($completedSafes / $totalSafes) * 100))
                Write-Progress -Activity "Retrieving Accounts" `
                    -Status "Safes: $completedSafes/$totalSafes | Accounts: $totalAccounts" `
                    -PercentComplete $pct
            }

            if ($completedSafes % 50 -eq 0) {
                LogOutput "Progress: $completedSafes/$totalSafes safes, $totalAccounts accounts"
            }
        }

        # Memory cleanup
        if ($totalAccounts % 50000 -eq 0 -and $totalAccounts -gt 0) {
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        }
    }

    # Wait for remaining jobs
    LogOutput "Waiting for $($jobs.Count) remaining jobs..."

    while ($jobs.Count -gt 0) {
        # Refresh token if needed
        if ((Get-Date) -gt $lastTokenRefresh.AddMinutes(15)) {
            try {
                $CybOnboardingRuntime.AuthTrimmed = Get-AuthToken
                $sharedState.AuthToken = $CybOnboardingRuntime.AuthTrimmed
                $lastTokenRefresh = Get-Date
                LogOutput "Token refreshed"
            } catch {}
        }

        $completedJobs = $jobs | Where-Object { $_.Handle.IsCompleted }

        foreach ($job in $completedJobs) {
            try {
                $result = $job.PowerShell.EndInvoke($job.Handle)

                if ($result -and $result.Count -gt 0) {
                    $safeResult = $result[0]

                    if ($safeResult.Error) {
                        LogError "Safe '$($safeResult.SafeName)': $($safeResult.Error)"
                    }

                    if ($safeResult.CsvLines -and $safeResult.CsvLines.Count -gt 0) {
                        Add-Content -Path $OutputPath -Value $safeResult.CsvLines -Encoding UTF8
                        $totalAccounts += $safeResult.Count
                    }
                }

                $completedSafes++

            } catch {
                LogError "Error: $($_.Exception.Message)"
                $completedSafes++
            } finally {
                $job.PowerShell.Dispose()
            }
        }

        foreach ($cj in $completedJobs) {
            $jobs.Remove($cj)
        }

        if ($jobs.Count -gt 0) {
            Start-Sleep -Seconds 2
        }

        if (-not $CybOnboardingRuntime.isAutosys) {
            $pct = [Math]::Min(100, [int](($completedSafes / $totalSafes) * 100))
            Write-Progress -Activity "Retrieving Accounts" `
                -Status "Safes: $completedSafes/$totalSafes | Accounts: $totalAccounts" `
                -PercentComplete $pct
        }
    }

    # Cleanup
    $runspacePool.Close()
    $runspacePool.Dispose()
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()

    if (-not $CybOnboardingRuntime.isAutosys) {
        Write-Progress -Activity "Retrieving Accounts" -Completed
    }

    $elapsed = (Get-Date) - $scriptStart
    LogOutput "Complete: $totalAccounts accounts from $totalSafes safes in $($elapsed.ToString('hh\:mm\:ss'))"

    $CybOnboardingRuntime.AccountsResult = $totalAccounts
}

function Process-UsersReport {
    [CmdletBinding()]
    param()

    try {
        LogOutput "Starting users report generation..."

        # Define output file names - Two separate files
        $TargetFileDetails = "Data_UserList_Details.csv"
        $TargetFileGroups = "Data_UserList_GroupMemberships.csv"

        # Retrieve all users from CyberArk with extended details
        $GetUsersResponse = Get-Users

        if ($GetUsersResponse -and $GetUsersResponse.Users) {
            # First export - Users with their group memberships
            $GetUsersResponse.Users | Select-Object -Property id, username, 
                @{Name = "GroupMembership"; Expression = { ($_.groupsMembership.groupName -join ';') }},
                source, userType, suspended |
                Export-Csv -Path (Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileGroups) -NoTypeInformation -UseCulture -Force

            LogOutput "Users Group Memberships Report written to $(Join-Path -Path $CybOnboardingRuntime.ConfDirLogs -ChildPath $TargetFileGroups)"

            # Convert vaultAuthorization from Object[] to String for better CSV formatting
            foreach ($User in $GetUsersResponse.Users) {
                $User.vaultAuthorization = [String]$User.vaultAuthorization
            }

            # Second export - Detailed user information
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

        # Define output file name and path
        $TargetFile = "Data_SafeDetails_Expanded.csv"

        # Retrieve all safes from CyberArk vault
        $allSafes = Get-AllSafes

        if ($allSafes -and $allSafes.Count -gt 0) {
            # Export safe details with selected properties
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
            ### This will try Cyberark authentication method
            $result = Invoke-RestMethod -Method Post -Uri $loginCybURI -Headers $headers -ContentType 'application/json; charset=utf-8' `
                -Body $Authentication -UseBasicParsing -ErrorAction Stop
            ### This will only execute if the Invoke-WebRequest is successful
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
            # PS5.1: Invoke-WebRequest with -ErrorAction Stop wraps HTTP errors as WebException,
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
