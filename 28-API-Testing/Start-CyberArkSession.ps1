#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [uri] $PvwaUri,
    [switch] $RunLive,
    [switch] $CopyTokenToClipboard
)

$ExitCode = 1
$Token = $null
$Headers = $null
$Body = $null
$Credential = $null
$Response = $null
$ClipboardSet = $false
$LogoffStatus = $null

try {
    if (-not $RunLive -or -not $CopyTokenToClipboard) {
        Write-Error -Message 'Specify -RunLive -CopyTokenToClipboard to start this interactive test.' -ErrorAction Stop
    }
    if (-not $PvwaUri.IsAbsoluteUri -or $PvwaUri.Scheme -ne 'https' -or $PvwaUri.UserInfo -or
        $PvwaUri.Query -or $PvwaUri.Fragment -or $PvwaUri.AbsolutePath.TrimEnd('/') -ne '/PasswordVault') {
        Write-Error -Message 'PvwaUri must be https://<host>[:port]/PasswordVault with no query.' -ErrorAction Stop
    }
    $null = Get-Command -Name Set-Clipboard, Get-Clipboard -ErrorAction Stop
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
    $Credential = Get-Credential -Message 'Native CyberArk test account, not SAML or Windows authentication'
    if ($null -eq $Credential) {
        Write-Error -Message 'Credentials were not supplied.' -ErrorAction Stop
    }
    $Body = @{
        username = $Credential.UserName
        password = $Credential.GetNetworkCredential().Password
        concurrentSession = $false
    } | ConvertTo-Json -Compress
    $Response = Invoke-WebRequest @Request -Method Post -Uri "$BaseUri/API/Auth/CyberArk/Logon" `
        -ContentType 'application/json' -Body $Body
    $Body = $null
    $Credential = $null
    if ([int] $Response.StatusCode -ne 200) {
        Write-Error -Message 'CyberArk logon did not return HTTP 200.' -ErrorAction Stop
    }
    $Token = ConvertFrom-Json -InputObject $Response.Content -ErrorAction Stop
    $Response = $null
    if ($Token -isnot [string] -or [string]::IsNullOrWhiteSpace($Token)) {
        Write-Error -Message 'CyberArk did not return a nonempty session token.' -ErrorAction Stop
    }
    $Headers = @{ Authorization = $Token }
    $Response = Invoke-WebRequest @Request -Method Get -Uri "$BaseUri/API/Safes?limit=1" -Headers $Headers
    $Data = ConvertFrom-Json -InputObject $Response.Content -ErrorAction Stop
    if ([int] $Response.StatusCode -ne 200 -or $null -eq $Data -or
        $null -eq $Data.PSObject.Properties['value']) {
        Write-Error -Message 'Server A could not establish a valid Safes API baseline.' -ErrorAction Stop
    }
    $Response = $null
    $Data = $null
    $ClipboardSet = $true
    Set-Clipboard -Value $Token -ErrorAction Stop
    [pscustomobject]@{
        TestName = 'ServerABaseline'
        Result = 'Pass'
        HttpStatus = 200
        TimestampUtc = [datetime]::UtcNow.ToString('o')
    }
    $null = Read-Host -Prompt 'Transfer the clipboard securely to Server B. Press Enter after B finishes to clean up'
    $ExitCode = 0
} catch {
    Write-Error -Message 'Server A test failed. Credentials, token and response details are suppressed.' `
        -ErrorAction Continue
} finally {
    if ($Token -is [string] -and -not [string]::IsNullOrWhiteSpace($Token)) {
        try {
            $Response = Invoke-WebRequest @Request -Method Post -Uri "$BaseUri/API/Auth/Logoff" -Headers $Headers
            $LogoffStatus = [int] $Response.StatusCode
            if ($LogoffStatus -notin 200, 204, 401) {
                $ExitCode = 1
            }
        } catch {
            $ExitCode = 1
        }
        if ($LogoffStatus -notin 200, 204, 401) {
            Write-Error -Message 'Logoff not confirmed on A. Ask the PAM operator to revoke the session.' `
                -ErrorAction Continue
        }
    }
    if ($ClipboardSet) {
        try {
            $ClipboardValue = Get-Clipboard -Raw -ErrorAction Stop
            if ($null -ne $ClipboardValue -and $ClipboardValue.TrimEnd([char[]] "`r`n") -ceq $Token) {
                Set-Clipboard -Value '' -ErrorAction Stop
            }
        } catch {
            $ExitCode = 1
            Write-Error -Message 'Clipboard cleanup failed on A. Clear it manually.' -ErrorAction Continue
        }
    }
    $Token = $null
    $Headers = $null
    $Body = $null
    $Credential = $null
    $Response = $null
    $Data = $null
    $ClipboardValue = $null
}

exit $ExitCode
