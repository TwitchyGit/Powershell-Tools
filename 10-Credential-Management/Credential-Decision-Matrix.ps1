<#
.SYNOPSIS
Maps automation scenarios to credential handling patterns.

.DESCRIPTION
The script returns a local decision matrix for common credential-management scenarios.

.NOTES
The matrix is training guidance. Local output does not prove live authentication.
#>
[CmdletBinding()]
param()

try {
    $Rows = @(
        [pscustomobject]@{
            Scenario = 'Scheduled local automation'
            Pattern = 'Managed service account or scheduled task identity'
            Avoid = 'Plain-text password in script'
            LiveValidation = 'Run as target account on target host'
        }
        [pscustomobject]@{
            Scenario = 'API call'
            Pattern = 'Short-lived token or vault-retrieved secret'
            Avoid = 'Token in log output'
            LiveValidation = 'Verify scope, expiry and revocation'
        }
        [pscustomobject]@{
            Scenario = 'WinRM to domain host'
            Pattern = 'Kerberos with domain hostname'
            Avoid = 'Wildcard TrustedHosts'
            LiveValidation = 'Run from approved management host'
        }
        [pscustomobject]@{
            Scenario = 'Client certificate auth'
            Pattern = 'Certificate with private key access'
            Avoid = 'Public certificate only'
            LiveValidation = 'Verify private key and server trust'
        }
        [pscustomobject]@{
            Scenario = 'CyberArk retrieval'
            Pattern = 'Retrieve at runtime with audited access'
            Avoid = 'Exported long-lived shared secret'
            LiveValidation = 'Verify PVWA or CCP response and audit record'
        }
    )

    $Rows
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
