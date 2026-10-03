<#
.SYNOPSIS
Shows short conditional expression syntax.

.DESCRIPTION
The script reports a compact status decision from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Ternary operator chooses one expression. It is best for short decisions.
    $Count = 3
    $Status = $Count -gt 0 ? 'Has items' : 'Empty'

    [pscustomobject]@{
        Stage = 'TernaryOperator'
        Count = $Count
        Status = $Status
        UseWhenSimple = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
