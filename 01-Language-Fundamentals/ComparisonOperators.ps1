<#
.SYNOPSIS
Shows comparison operator behavior.

.DESCRIPTION
The script reports string, number and date comparison results from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # PowerShell comparisons are case-insensitive by default for strings.
    $DefaultMatch = 'PowerShell' -eq 'powershell'

    # Prefix c makes comparison case-sensitive.
    $CaseSensitiveMatch = 'PowerShell' -ceq 'powershell'

    [pscustomobject]@{
        Stage = 'ComparisonOperators'
        DefaultMatch = $DefaultMatch
        CaseSensitiveMatch = $CaseSensitiveMatch
        NumberMatch = 7 -eq '7'
        DateAfter = [datetime]'2026-02-01' -gt [datetime]'2026-01-01'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
