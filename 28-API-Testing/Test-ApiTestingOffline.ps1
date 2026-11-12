#Requires -Version 7.6
[CmdletBinding()]
param()

$ExitCode = 0
$FixtureToken = 'synthetic-offline-session-token'
$FixturePassword = 'synthetic-offline-password'
$FailureCount = 0
$Cases = @(
    @{ Name = 'ReplayThenRevoked'; Status = @(200, 200, 401); Exit = 0; Result = 'Pass'; Calls = 3 },
    @{ Name = 'ReplayStillAccepted'; Status = @(200, 200, 200); Exit = 1; Result = 'Fail'; Calls = 3 },
    @{ Name = 'VerificationForbidden'; Status = @(200, 200, 403); Exit = 1; Result = 'Inconclusive'; Calls = 3 },
    @{ Name = 'VerificationServerError'; Status = @(200, 200, 500); Exit = 1; Result = 'Inconclusive'; Calls = 3 },
    @{ Name = 'VerificationNetworkError'; Status = @(200, 200, 0); Exit = 1; Result = 'Inconclusive'; Calls = 3 },
    @{ Name = 'BaselineUnauthorized'; Status = @(401, 200); Exit = 1; Result = 'Inconclusive'; Calls = 2 },
    @{ Name = 'BaselineForbidden'; Status = @(403, 200); Exit = 1; Result = 'Inconclusive'; Calls = 2 },
    @{ Name = 'BaselineNetworkError'; Status = @(0, 200); Exit = 1; Result = 'Inconclusive'; Calls = 2 },
    @{ Name = 'BaselineHtml'; Status = @(200, 200); Html = $true; Exit = 1; Result = 'Inconclusive'; Calls = 2 },
    @{ Name = 'LogoffFailure'; Status = @(200, 500, 200); Exit = 1; Result = 'Inconclusive'; Calls = 3 },
    @{ Name = 'ReplayGuard'; Status = @(); NoLive = $true; Exit = 1; Result = 'Inconclusive'; Calls = 0 },
    @{ Name = 'RejectHttp'; Status = @(); Http = $true; Exit = 1; Result = 'Inconclusive'; Calls = 0 },
    @{ Name = 'EmptyToken'; Status = @(); Empty = $true; Exit = 1; Result = 'Inconclusive'; Calls = 0 },
    @{ Name = 'ServerALogon'; A = $true; Status = @(200, 200, 200); Exit = 0; Calls = 3 },
    @{ Name = 'ServerAAlreadyRevoked'; A = $true; Status = @(200, 200, 401); Exit = 0; Calls = 3 },
    @{ Name = 'ServerABadCredentials'; A = $true; Status = @(401); Exit = 1; Calls = 1 },
    @{ Name = 'ServerABaselineDenied'; A = $true; Status = @(200, 403, 200); Exit = 1; Calls = 3 },
    @{ Name = 'ServerACleanupFailure'; A = $true; Status = @(200, 200, 500); Exit = 1; Calls = 3 },
    @{ Name = 'ServerAGuard'; A = $true; Status = @(); NoLive = $true; Exit = 1; Calls = 0 }
)

function Get-Credential {
    [CmdletBinding()]
    param([string] $Message)
    [pscredential]::new('OfflineTestUser', (ConvertTo-SecureString -String $FixturePassword -AsPlainText -Force))
}

function Read-Host {
    [CmdletBinding()]
    param(
        [string] $Prompt,
        [switch] $AsSecureString
    )
    if ($AsSecureString) {
        if ($Case.Empty) {
            return [securestring]::new()
        }
        return ConvertTo-SecureString -String $FixtureToken -AsPlainText -Force
    }
    return ''
}

function Set-Clipboard {
    [CmdletBinding()]
    param([string] $Value)
    $MockState.Clipboard = $Value
}

function Get-Clipboard {
    [CmdletBinding()]
    param([switch] $Raw)
    $MockState.Clipboard
}

function Invoke-WebRequest {
    [CmdletBinding()]
    param(
        [string] $Method,
        [uri] $Uri,
        [hashtable] $Headers,
        [string] $Body,
        [string] $ContentType,
        [int] $ConnectionTimeoutSeconds,
        [int] $OperationTimeoutSeconds,
        [int] $MaximumRedirection,
        [int] $MaximumRetryCount,
        [switch] $SkipHttpErrorCheck
    )
    $MockState.CallIndex++
    if ($MockState.CallIndex -gt $Case.Status.Count) {
        $MockState.MockFailure = 'Unexpected request count.'
        Write-Error -Message $MockState.MockFailure -ErrorAction Stop
    }
    $Path = $Uri.AbsolutePath
    $IsLogon = $Path -eq '/PasswordVault/API/Auth/CyberArk/Logon'
    $IsLogoff = $Path -eq '/PasswordVault/API/Auth/Logoff'
    $IsRead = $Path -eq '/PasswordVault/API/Safes' -and $Uri.Query -eq '?limit=1'
    if ($Uri.Host -ne 'offline.invalid' -or $Uri.Scheme -ne 'https' -or
        ($IsLogon -and $Method -ne 'Post') -or ($IsLogoff -and $Method -ne 'Post') -or
        ($IsRead -and $Method -ne 'Get') -or (-not ($IsLogon -or $IsLogoff -or $IsRead)) -or
        (-not $IsLogon -and $Headers.Authorization -cne $FixtureToken) -or
        $MaximumRedirection -ne 0 -or $MaximumRetryCount -ne 0 -or -not $SkipHttpErrorCheck -or
        $ConnectionTimeoutSeconds -ne 15 -or $OperationTimeoutSeconds -ne 30) {
        $MockState.MockFailure = 'Request endpoint, token, method or transport options did not match.'
        Write-Error -Message $MockState.MockFailure -ErrorAction Stop
    }
    if ($IsLogon) {
        $Login = ConvertFrom-Json -InputObject $Body
        if ($Login.username -cne 'OfflineTestUser' -or $Login.password -cne $FixturePassword -or
            $Login.concurrentSession -ne $false -or $ContentType -ne 'application/json') {
            $MockState.MockFailure = 'Logon body did not match the fixture.'
            Write-Error -Message $MockState.MockFailure -ErrorAction Stop
        }
    }
    $Status = $Case.Status[$MockState.CallIndex - 1]
    if ($Status -eq 0) {
        Write-Error -Message 'Synthetic network failure.' -ErrorAction Stop
    }
    $Content = if ($IsLogon) {
        ConvertTo-Json -InputObject $FixtureToken
    } elseif ($Case.Html -and $MockState.CallIndex -eq 1) {
        '<html>synthetic login page</html>'
    } else {
        '{"value":[]}'
    }
    [pscustomobject]@{ StatusCode = $Status; Content = $Content }
}

foreach ($Case in $Cases) {
    $MockState = @{ CallIndex = 0; MockFailure = $null; Clipboard = '' }
    $ScriptName = if ($Case.A) { 'Start-CyberArkSession.ps1' } else { 'Test-CyberArkTokenReplay.ps1' }
    $Parameters = @{
        PvwaUri = if ($Case.Http) { 'http://offline.invalid/PasswordVault' } else {
            'https://offline.invalid/PasswordVault'
        }
        RunLive = -not $Case.NoLive
    }
    if ($Case.A) {
        $Parameters.CopyTokenToClipboard = $true
    }
    $Output = & (Join-Path -Path $PSScriptRoot -ChildPath $ScriptName) @Parameters 2>&1 3>&1
    $ActualExit = $LASTEXITCODE
    $Actual = @($Output | Where-Object { $_.PSObject.Properties['TestName'] })
    $OutputText = $Output | Out-String
    $Passed = $ActualExit -eq $Case.Exit -and $MockState.CallIndex -eq $Case.Calls -and
        $null -eq $MockState.MockFailure -and $MockState.Clipboard -eq '' -and
        -not $OutputText.Contains($FixtureToken) -and -not $OutputText.Contains($FixturePassword)
    if ($Case.Result) {
        $Passed = $Passed -and $Actual.Count -eq 1 -and $Actual[0].Result -eq $Case.Result
    }
    if (-not $Passed) {
        $FailureCount++
        $ExitCode = 1
        Write-Warning -Message "$($Case.Name): exit=$ActualExit calls=$MockState.CallIndex mock=$MockState.MockFailure"
    }
    [pscustomobject]@{
        TestName = $Case.Name
        Result = if ($Passed) { 'Pass' } else { 'Fail' }
        Evidence = 'Mocked requests only, no network or real clipboard access'
    }
}

if ($FailureCount -gt 0) {
    Write-Error -Message "$FailureCount offline checks failed." -ErrorAction Continue
}
exit $ExitCode
