param(
    [string]$CsvFolder = '.'
)

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module .\ADAccountsMonitor.psm1 -ErrorAction Stop

function Encode-Html {
    param(
        [string]$Text
    )
    if ($null -eq $Text) {
        return ''
    }

    $t = $Text.Replace('&','&amp;')
    $t = $t.Replace('<','&lt;')
    $t = $t.Replace('>','&gt;')
    $t = $t.Replace('"','&quot;')
    $t = $t.Replace("'",'&#39;')
    return $t
}

function Test-AccountHealth {
    param(
        [string]$DomainName,      # DOMAIN1 / DOMAIN2 (also used as -Server)
        [string]$SamAccountName   # account1 / svc_app1 etc
    )

    $netbios = $DomainName
    $sam     = $SamAccountName

    try {
        # Assumes DomainName is resolvable as an AD server (NetBIOS or DNS)
        $user = Get-ADUser -Identity $sam -Server $DomainName -ErrorAction Stop -Properties Enabled,LockedOut,AccountExpirationDate,PasswordExpired,PasswordLastSet,UserAccountControl
    } catch {
        return [pscustomobject]@{
            Environment    = $script:CurrentEnvironment
            Domain         = $DomainName
            NetbiosDomain  = $netbios
            SamAccountName = $sam
            Status         = 'Error'
            Reason         = "Get-ADUser failed: $($_.Exception.Message)"
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
        Environment    = $script:CurrentEnvironment
        Domain         = $DomainName
        NetbiosDomain  = $netbios
        SamAccountName = $sam
        Status         = $status
        Reason         = $reason
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
        Write-Output 'ERROR: SmtpServer, From and To must be specified for email sending'
        return
    }

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
  <p><b>Environments:</b> $(Encode-Html $envList)<br />
     <b>Generated:</b> $(Encode-Html $timeStr)</p>
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
        $env  = Encode-Html $i.Environment
        $dom  = Encode-Html $i.Domain
        $nb   = Encode-Html $i.NetbiosDomain
        $sam  = Encode-Html $i.SamAccountName
        $stat = Encode-Html $i.Status
        $reas = Encode-Html $i.Reason

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
        if ($mail) { $mail.Dispose() }
        if ($smtp) { $smtp.Dispose() }
    }
}

# Validate that ConfigModule has given us Environment and AccountList

if (-not (Get-Variable -Name Environment -ErrorAction SilentlyContinue)) {
    Write-Output 'ERROR: Environment variable not defined by ConfigModule'
    exit 1
}

if (-not (Get-Variable -Name AccountList -ErrorAction SilentlyContinue)) {
    Write-Output 'ERROR: AccountList variable not defined by ConfigModule'
    exit 1
}

$script:CurrentEnvironment = [string]$Environment
$accountsByDomain = $AccountList

if (-not $accountsByDomain -or $accountsByDomain.Count -eq 0) {
    Write-Output "WARN: No domains or accounts defined for env '$script:CurrentEnvironment'"
    exit 0
}

Write-Output "INFO: Starting account health check for environment '$script:CurrentEnvironment'"

$results = @()

foreach ($domainName in $accountsByDomain.Keys) {
    $accountList = $accountsByDomain[$domainName]
    if (-not $accountList -or $accountList.Count -eq 0) {
        Write-Output "WARN: No accounts listed for domain '$domainName' in env '$script:CurrentEnvironment'"
        continue
    }

    foreach ($sam in $accountList) {
        $result = Test-AccountHealth -DomainName $domainName -SamAccountName $sam
        $results += $result

        # Log one line per account for Autosys logs
        Write-Output ("INFO: {0} {1}\{2} Status={3} Reason={4}" -f `
            $result.Environment, $result.NetbiosDomain, $result.SamAccountName, $result.Status, $result.Reason)
    }
}

if (-not $results -or $results.Count -eq 0) {
    Write-Output 'WARN: No results generated'
    exit 0
}

# Ensure CSV folder exists
if (-not (Test-Path -LiteralPath $CsvFolder)) {
    New-Item -Path $CsvFolder -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath   = Join-Path -Path $CsvFolder -ChildPath ("AccountHealth_{0}_{1}.csv" -f $script:CurrentEnvironment, $timestamp)

$results | Export-Csv -NoTypeInformation -Path $csvPath
Write-Output "INFO: Account health CSV written to '$csvPath'"

# Call email function (fill these in with real values)
Send-AccountHealthEmail -Results $results `
    -CsvPath $csvPath `
    -SmtpServer 'your.smtp.server' `
    -SmtpPort 25 `
    -From 'account-monitor@yourdomain' `
    -To 'pamsupport@yourdomain' `
    -Subject "Account health issues detected in $($script:CurrentEnvironment)" `
    -UseSsl
