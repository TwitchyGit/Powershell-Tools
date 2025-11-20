param(
    [string]$CfgPath   = '.\monitor_accounts.cfg',
    [string]$CsvFolder = '.'
)

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module .\ADAccountsMonitor.psm1 -ErrorAction Stop

function Get-EnvFromCfg {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Output "WARN: cfg file '$Path' not found, defaulting to DEV"
        return 'DEV'
    }

    $lines = Get-Content -LiteralPath $Path | Where-Object {$_ -and $_ -notmatch '^\s*#'}
    foreach ($line in $lines) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2 -and $parts[0].Trim() -ieq 'Environment') {
            return $parts[1].Trim()
        }
    }

    Write-Output "WARN: Environment not found in cfg, defaulting to DEV"
    return 'DEV'
}

function Test-AccountHealth {
    param(
        [string]$DomainDns,
        [string]$AccountString
    )

    # AccountString is DOMAIN\SamAccountName
    $split = $AccountString -split '\\', 2
    if ($split.Count -ne 2) {
        return [pscustomobject]@{
            Environment      = $script:CurrentEnvironment
            Domain           = $DomainDns
            NetbiosDomain    = $null
            SamAccountName   = $AccountString
            Status           = 'Error'
            Reason           = 'Account string not in DOMAIN\Sam format'
        }
    }

    $netbios = $split[0]
    $sam     = $split[1]

    try {
        $user = Get-ADUser -Identity $sam -Server $DomainDns -ErrorAction Stop -Properties Enabled,LockedOut,AccountExpirationDate,PasswordExpired,PasswordLastSet,UserAccountControl
    } catch {
        return [pscustomobject]@{
            Environment      = $script:CurrentEnvironment
            Domain           = $DomainDns
            NetbiosDomain    = $netbios
            SamAccountName   = $sam
            Status           = 'Error'
            Reason           = "Get-ADUser failed: $($_.Exception.Message)"
        }
    }

    $now    = Get-Date
    $status = 'OK'
    $reason = ''

    if (-not $user.Enabled) {
        $status = 'NotUsable'
        $reason = 'Disabled'
    } elseif ($user.LockedOut) {
        $status = 'NotUsable'
        $reason = 'LockedOut'
    } elseif ($user.AccountExpirationDate -and ($user.AccountExpirationDate -le $now)) {
        $status = 'NotUsable'
        $reason = 'AccountExpired'
    } elseif ($user.PasswordExpired) {
        $status = 'NotUsable'
        $reason = 'PasswordExpired'
    }

    return [pscustomobject]@{
        Environment      = $script:CurrentEnvironment
        Domain           = $DomainDns
        NetbiosDomain    = $netbios
        SamAccountName   = $sam
        Status           = $status
        Reason           = $reason
    }
}

function Send-AccountHealthEmail {
    param(
        [System.Collections.IEnumerable]$Results,
        [string]$CsvPath,
        [string]$SmtpServer,
        [int]$SmtpPort = 25,
        [string]$From,
        [string]$To,
        [string]$Subject = 'Account health issues detected',
        [switch]$UseSsl
    )

    if (-not $Results) {
        Write-Output 'WARN: No results passed to Send-AccountHealthEmail'
        return
    }

    # Any status not equal to OK is considered an issue
    $issues = $Results | Where-Object { $_.Status -ne 'OK' }

    if (-not $issues -or $issues.Count -eq 0) {
        Write-Output 'INFO: All accounts OK, no email generated'
        return
    }

    if (-not $SmtpServer -or -not $From -or -not $To) {
        Write-Output 'ERROR: SmtpServer, From, and To must be specified for email sending'
        return
    }

    # Build simple HTML body
    $envList = ($issues | Select-Object -ExpandProperty Environment -Unique) -join ', '
    $timeStr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    $html = @"
<html>
<head>
  <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
  <style type="text/css">
    body { font-family: Arial, sans-serif; font-size: 11px; }
    table { border-collapse: collapse; }
    th, td { border: 1px solid #999999; padding: 4px 6px; }
    th { background-color: #eeeeee; }
  </style>
</head>
<body>
  <p>Account health issues were detected.</p>
  <p><b>Environments:</b> $envList<br />
     <b>Generated:</b> $timeStr</p>
  <table>
    <tr>
      <th>Environment</th>
      <th>Domain</th>
      <th>NetbiosDomain</th>
      <th>SamAccountName</th>
      <th>Status</th>
      <th>Reason</th>
    </tr>
"@

    foreach ($i in $issues) {
        $env   = [System.Web.HttpUtility]::HtmlEncode($i.Environment)
        $dom   = [System.Web.HttpUtility]::HtmlEncode($i.Domain)
        $nb    = [System.Web.HttpUtility]::HtmlEncode($i.NetbiosDomain)
        $sam   = [System.Web.HttpUtility]::HtmlEncode($i.SamAccountName)
        $stat  = [System.Web.HttpUtility]::HtmlEncode($i.Status)
        $reas  = [System.Web.HttpUtility]::HtmlEncode($i.Reason)

        $html += @"
    <tr>
      <td>$env</td>
      <td>$dom</td>
      <td>$nb</td>
      <td>$sam</td>
      <td>$stat</td>
      <td>$reas</td>
    </tr>
"@
    }

    $html += @"
  </table>
"@

    if ($CsvPath -and (Test-Path -LiteralPath $CsvPath)) {
        $html += "<p>Full account health details are attached as CSV.</p>"
    }

    $html += @"
</body>
</html>
"@

    try {
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = $From
        $mail.To.Add($To)
        $mail.Subject = $Subject
        $mail.IsBodyHtml = $true
        $mail.Body = $html

        if ($CsvPath -and (Test-Path -LiteralPath $CsvPath)) {
            $attachment = New-Object System.Net.Mail.Attachment($CsvPath)
            $mail.Attachments.Add($attachment) | Out-Null
        }

        $smtp = New-Object System.Net.Mail.SmtpClient($SmtpServer, $SmtpPort)
        if ($UseSsl) {
            $smtp.EnableSsl = $true
        }

        Write-Output 'INFO: Sending account health email with issues'
        $smtp.Send($mail)
        Write-Output 'INFO: Account health email sent'
    } catch {
        Write-Output "ERROR: Failed to send email: $($_.Exception.Message)"
    } finally {
        if ($mail) {
            $mail.Dispose()
        }
        if ($smtp) {
            $smtp.Dispose()
        }
    }
}

$script:CurrentEnvironment = Get-EnvFromCfg -Path $CfgPath

if (-not $ConfAccountSets.ContainsKey($script:CurrentEnvironment)) {
    Write-Output "ERROR: Environment '$script:CurrentEnvironment' not defined in ConfigModule"
    exit 1
}

$accountsByDomain = $ConfAccountSets[$script:CurrentEnvironment]

if (-not $accountsByDomain -or $accountsByDomain.Count -eq 0) {
    Write-Output "WARN: No domains or accounts defined for env '$script:CurrentEnvironment'"
    exit 0
}

Write-Output "INFO: Starting account health check for environment '$script:CurrentEnvironment'"

$results = @()

foreach ($domain in $accountsByDomain.Keys) {
    $accountList = $accountsByDomain[$domain]
    if (-not $accountList -or $accountList.Count -eq 0) {
        Write-Output "WARN: No accounts listed for domain '$domain' in env '$script:CurrentEnvironment'"
        continue
    }

    foreach ($acct in $accountList) {
        $result = Test-AccountHealth -DomainDns $domain -AccountString $acct
        $results += $result

        Write-Output ("INFO: {0} {1}\{2} Status={3} Reason={4}" -f `
            $result.Environment, $result.NetbiosDomain, $result.SamAccountName, $result.Status, $result.Reason)
    }
}

if (-not $results -or $results.Count -eq 0) {
    Write-Output 'WARN: No results generated'
    exit 0
}

# Export CSV
if (-not (Test-Path -LiteralPath $CsvFolder)) {
    New-Item -Path $CsvFolder -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath   = Join-Path -Path $CsvFolder -ChildPath ("AccountHealth_{0}_{1}.csv" -f $script:CurrentEnvironment, $timestamp)

$results | Export-Csv -NoTypeInformation -Path $csvPath
Write-Output "INFO: Account health CSV written to '$csvPath'"

# Call email function
# Plug in your real SMTP values here
Send-AccountHealthEmail -Results $results `
    -CsvPath $csvPath `
    -SmtpServer 'your.smtp.server' `
    -SmtpPort 25 `
    -From 'account-monitor@yourdomain' `
    -To 'pamsupport@yourdomain' `
    -Subject "Account health issues detected in $($script:CurrentEnvironment)" `
    -UseSsl
