<#
.SYNOPSIS
    Monitors Active Directory account health across multiple domains and sends email alerts for issues.

.DESCRIPTION
    This script checks the health status of specified Active Directory accounts across one or more domains.
    It identifies accounts that are disabled, locked out, expired, or have expired passwords.
    Results are exported to CSV and email notifications are sent when issues are detected.
    
    The script expects the ConfigModule to define:
    - $Environment: The current environment name (e.g., "Production", "Test")
    - $AccountList: A hashtable where keys are domain names and values are arrays of SamAccountNames

.PARAMETER CsvFolder
    The folder path where CSV output files will be saved. Defaults to current directory.

.EXAMPLE
    .\AccountHealthMonitor.ps1 -CsvFolder "C:\Logs"

.NOTES
    Requires: Active Directory PowerShell module and ADAccountsMonitor.psm1
    Author: Account Health Monitor
    Version: 1.0
#>

param(
    [string]$CsvFolder = '.'
)

# Import only the required cmdlet from Active Directory module to minimize load time
Import-Module ActiveDirectory -Cmdlet Get-ADUser -ErrorAction Stop
Import-Module .\ADAccountsMonitor.psm1 -ErrorAction Stop

#region Helper Functions

function Encode-Html {
    <#
    .SYNOPSIS
        Encodes text for safe HTML output by escaping special characters.
    #>
    param(
        [string]$Text
    )
    if ($null -eq $Text) {
        return ''
    }

    # Escape HTML special characters to prevent injection and rendering issues
    $t = $Text.Replace('&','&amp;')
    $t = $t.Replace('<','&lt;')
    $t = $t.Replace('>','&gt;')
    $t = $t.Replace('"','&quot;')
    $t = $t.Replace("'",'&#39;')
    return $t
}

function Test-AccountHealth {
    <#
    .SYNOPSIS
        Tests the health status of a single Active Directory account.
    
    .DESCRIPTION
        Queries AD for the specified account and checks for common issues:
        - Account disabled
        - Account locked out
        - Account expired
        - Password expired
    #>
    param(
        [string]$DomainName,      # Domain name (NetBIOS or DNS) - also used as -Server parameter
        [string]$SamAccountName   # Account login name (e.g., account1, svc_app1)
    )

    $netbios = $DomainName
    $sam     = $SamAccountName

    try {
        # Query Active Directory for the user account with health-related properties
        # Assumes DomainName is resolvable as an AD server (NetBIOS or DNS name)
        $user = Get-ADUser -Identity $sam -Server $DomainName -ErrorAction Stop `
            -Properties Enabled, LockedOut, AccountExpirationDate, PasswordExpired, PasswordLastSet, UserAccountControl
    } catch {
        # Return error object if account cannot be queried
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

    # Check for account health issues in priority order
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

    # Return health status object
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
    <#
    .SYNOPSIS
        Sends an email notification when account health issues are detected.
    
    .DESCRIPTION
        Generates an HTML email containing a table of all accounts with issues.
        Optionally attaches the full CSV report. Only sends email if issues exist.
    #>
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

    # Filter to only accounts with issues (any status not equal to OK)
    $issues = $Results | Where-Object { $_.Status -ne 'OK' }

    if (-not $issues -or $issues.Count -eq 0) {
        Write-Output 'INFO: All accounts OK, no email generated'
        return
    }

    # Validate required email parameters
    if (-not $SmtpServer -or -not $From -or -not $To) {
        Write-Output 'ERROR: SmtpServer, From and To must be specified for email sending'
        return
    }

    # Prepare email metadata
    $envList = ($issues | Select-Object -ExpandProperty Environment -Unique) -join ', '
    $timeStr = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    # Build HTML email body with embedded styles and issue table
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

    # Add a table row for each account issue
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

    # Add note about CSV attachment if file exists
    if ($CsvPath -and (Test-Path -LiteralPath $CsvPath)) {
        $html += "<p>Full account health details are attached as CSV.</p>"
    }

    $html += @"
</body>
</html>
"@

    try {
        # Create and configure email message
        $mail = New-Object System.Net.Mail.MailMessage
        $mail.From = $From
        $mail.To.Add($To)
        $mail.Subject = $Subject
        $mail.IsBodyHtml = $true
        $mail.Body = $html

        # Attach CSV file if it exists
        if ($CsvPath -and (Test-Path -LiteralPath $CsvPath)) {
            $attachment = New-Object System.Net.Mail.Attachment($CsvPath)
            $mail.Attachments.Add($attachment) | Out-Null
        }

        # Configure SMTP client and send email
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
        # Clean up disposable objects
        if ($mail) { $mail.Dispose() }
        if ($smtp) { $smtp.Dispose() }
    }
}

#endregion

#region Main Script Logic

# Validate that ConfigModule has provided required variables
if (-not (Get-Variable -Name Environment -ErrorAction SilentlyContinue)) {
    Write-Output 'ERROR: Environment variable not defined by ConfigModule'
    exit 1
}

if (-not (Get-Variable -Name AccountList -ErrorAction SilentlyContinue)) {
    Write-Output 'ERROR: AccountList variable not defined by ConfigModule'
    exit 1
}

# Store current environment name in script scope for use in functions
$script:CurrentEnvironment = [string]$Environment
$accountsByDomain = $AccountList

# Validate that we have accounts to check
if (-not $accountsByDomain -or $accountsByDomain.Count -eq 0) {
    Write-Output "WARN: No domains or accounts defined for env '$script:CurrentEnvironment'"
    exit 0
}

Write-Output "INFO: Starting account health check for environment '$script:CurrentEnvironment'"

# Initialize results array to store health check outcomes
$results = @()

# Process each domain and its associated accounts
foreach ($domainName in $accountsByDomain.Keys) {
    $accountList = $accountsByDomain[$domainName]
    
    if (-not $accountList -or $accountList.Count -eq 0) {
        Write-Output "WARN: No accounts listed for domain '$domainName' in env '$script:CurrentEnvironment'"
        continue
    }

    # Check health for each account in this domain
    foreach ($sam in $accountList) {
        $result = Test-AccountHealth -DomainName $domainName -SamAccountName $sam
        $results += $result

        # Log one line per account for operational visibility (e.g., Autosys logs)
        Write-Output "INFO: $($result.Environment) $($result.NetbiosDomain)\$($result.SamAccountName) Status=$($result.Status) Reason=$($result.Reason)"
    }
}

# Validate that we generated results
if (-not $results -or $results.Count -eq 0) {
    Write-Output 'WARN: No results generated'
    exit 0
}

# Ensure CSV output folder exists, create if necessary
if (-not (Test-Path -LiteralPath $CsvFolder)) {
    New-Item -Path $CsvFolder -ItemType Directory -Force | Out-Null
}

# Generate timestamped CSV filename
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$csvPath   = Join-Path -Path $CsvFolder -ChildPath "AccountHealth_$($script:CurrentEnvironment)_$timestamp.csv"

# Export all results to CSV for record keeping
$results | Export-Csv -NoTypeInformation -Path $csvPath
Write-Output "INFO: Account health CSV written to '$csvPath'"

# Send email notification if issues were detected
# TODO: Replace placeholder email settings with actual values
Send-AccountHealthEmail -Results $results `
    -CsvPath $csvPath `
    -SmtpServer 'your.smtp.server' `
    -SmtpPort 25 `
    -From 'account-monitor@yourdomain' `
    -To 'pamsupport@yourdomain' `
    -Subject "Account health issues detected in $($script:CurrentEnvironment)" `
    -UseSsl

#endregion
