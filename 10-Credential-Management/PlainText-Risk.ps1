<#
.SYNOPSIS
Shows why plain-text secret values are unsafe in automation.

.DESCRIPTION
The script uses synthetic secret values to demonstrate accidental disclosure through output, logs and object properties.

.NOTES
This script is training material. It does not read or write real credentials.
#>
[CmdletBinding()]
param()

try {
    $SampleSecret = 'TrainingSecret-DoNotUse'
    $RedactedSecret = $SampleSecret -replace '.', '*'
    $RiskItems = @(
        [pscustomobject]@{
            Location = 'Console output'
            Risk = 'Plain strings can appear in captured output.'
            SafePattern = 'Return metadata and redact the value.'
        }
        [pscustomobject]@{
            Location = 'Log file'
            Risk = 'Plain strings can persist beyond the process lifetime.'
            SafePattern = 'Write a secret reference, hash or redacted preview.'
        }
        [pscustomobject]@{
            Location = 'Error message'
            Risk = 'Exceptions can include command arguments.'
            SafePattern = 'Validate before command construction.'
        }
    )

    foreach ($RiskItem in $RiskItems) {
        [pscustomobject]@{
            Location = $RiskItem.Location
            Risk = $RiskItem.Risk
            SafePattern = $RiskItem.SafePattern
            SecretPreview = $RedactedSecret.Substring(0, 8)
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
