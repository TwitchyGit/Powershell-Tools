<#
.SYNOPSIS
Shows null fallback behavior.

.DESCRIPTION
The script reports fallback behavior for null and empty string values.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Null-coalescing returns fallback only when left side is null.
    $Missing = $null
    $Empty = ''

    [pscustomobject]@{
        Stage = 'NullCoalescing'
        MissingFallback = $Missing ?? 'fallback'
        EmptyFallback = $Empty ?? 'fallback'
        EmptyWasNull = $null -eq $Empty
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
