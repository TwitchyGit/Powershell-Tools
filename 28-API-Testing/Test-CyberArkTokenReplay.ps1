#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [uri] $PvwaUri,
    [switch] $RunLive
)

$ExitCode = 1
$Token = $null
$SecureToken = $null
$Headers = $null
$Response = $null
$LogoffSucceeded = $false
$Stage = 'Input'
$BeforeStatus = $null
$LogoffStatus = $null
$AfterStatus = $null
$Result = 'Inconclusive'
$Observed = 'Test did not complete.'
$Timer = [diagnostics.stopwatch]::StartNew()

try {
    if (-not $RunLive) {
        Write-Error -Message 'Specify -RunLive to test and log off the supplied session.' -ErrorAction Stop
    }
    if (-not $PvwaUri.IsAbsoluteUri -or $PvwaUri.Scheme -ne 'https' -or $PvwaUri.UserInfo -or
        $PvwaUri.Query -or $PvwaUri.Fragment -or $PvwaUri.AbsolutePath.TrimEnd('/') -ne '/PasswordVault') {
        Write-Error -Message 'PvwaUri must be https://<host>[:port]/PasswordVault with no query.' -ErrorAction Stop
    }
    $BaseUri = $PvwaUri.AbsoluteUri.TrimEnd('/')
    $Request = @{
        ConnectionTimeoutSeconds = 15
        OperationTimeoutSeconds = 30
        MaximumRedirection = 0
        MaximumRetryCount = 0
        SkipHttpErrorCheck = $true
        ErrorAction = 'Stop'
        Verbose = $false
        Debug = $false
    }
    $SecureToken = Read-Host -Prompt 'Paste the session token from Server A' -AsSecureString
    $Token = [pscredential]::new('SessionToken', $SecureToken).GetNetworkCredential().Password
    if ([string]::IsNullOrWhiteSpace($Token)) {
        Write-Error -Message 'A nonempty session token is required.' -ErrorAction Stop
    }
    $Headers = @{ Authorization = $Token }
    $Stage = 'ReplayRead'
    $Response = Invoke-WebRequest @Request -Method Get -Uri "$BaseUri/API/Safes?limit=1" -Headers $Headers
    $BeforeStatus = [int] $Response.StatusCode
    if ($BeforeStatus -ne 200) {
        Write-Error -Message 'Server B did not establish a successful read baseline.' -ErrorAction Stop
    }
    $Data = ConvertFrom-Json -InputObject $Response.Content -ErrorAction Stop
    if ($null -eq $Data -or $null -eq $Data.PSObject.Properties['value']) {
        Write-Error -Message 'Server B did not receive the expected Safes JSON response.' -ErrorAction Stop
    }
    $Data = $null
    $Response = $null
    $Stage = 'Logoff'
    $Response = Invoke-WebRequest @Request -Method Post -Uri "$BaseUri/API/Auth/Logoff" -Headers $Headers
    $LogoffStatus = [int] $Response.StatusCode
    $LogoffSucceeded = $LogoffStatus -in 200, 204
    if (-not $LogoffSucceeded) {
        Write-Error -Message 'Server B could not confirm successful logoff.' -ErrorAction Stop
    }
    $Stage = 'VerificationRead'
    $Response = Invoke-WebRequest @Request -Method Get -Uri "$BaseUri/API/Safes?limit=1" -Headers $Headers
    $AfterStatus = [int] $Response.StatusCode
    if ($AfterStatus -eq 401) {
        $Result = 'Pass'
        $Observed = 'Token reuse succeeded before logoff. The same read returned HTTP 401 after logoff.'
        $ExitCode = 0
    } elseif ($AfterStatus -ge 200 -and $AfterStatus -lt 300) {
        $Result = 'Fail'
        $Observed = 'The read still succeeded after logoff. Investigate session invalidation.'
    } else {
        $Observed = 'The verification response does not establish token invalidation.'
    }
} catch {
    $Observed = "Test stopped at $Stage. Network, input or API response needs investigation."
} finally {
    if ($null -ne $Headers -and -not $LogoffSucceeded) {
        try {
            $Response = Invoke-WebRequest @Request -Method Post -Uri "$BaseUri/API/Auth/Logoff" -Headers $Headers
            $CleanupStatus = [int] $Response.StatusCode
            if ($CleanupStatus -notin 200, 204, 401) {
                Write-Warning -Message 'Cleanup was not confirmed. Ask the PAM operator to revoke the session.'
            }
        } catch {
            Write-Warning -Message 'Cleanup failed. Ask the PAM operator to revoke the session.'
        }
    }
    $Token = $null
    $Headers = $null
    $Response = $null
    $Data = $null
    if ($null -ne $SecureToken) {
        $SecureToken.Dispose()
        $SecureToken = $null
    }
    $Timer.Stop()
}

[pscustomobject]@{
    TestName = 'TokenReplayAndLogoff'
    Result = $Result
    Observed = $Observed
    Stage = $Stage
    ReplayHttpStatus = $BeforeStatus
    LogoffHttpStatus = $LogoffStatus
    VerificationHttpStatus = $AfterStatus
    DurationMs = $Timer.ElapsedMilliseconds
    TimestampUtc = [datetime]::UtcNow.ToString('o')
}
if ($ExitCode -ne 0) {
    Write-Error -Message 'Replay test failed or was inconclusive. Review the sanitised result.' -ErrorAction Continue
}
exit $ExitCode
