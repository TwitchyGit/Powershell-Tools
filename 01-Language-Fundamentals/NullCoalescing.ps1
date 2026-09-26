[CmdletBinding()]
param()

try {
    # Null-coalescing returns fallback only when left side is null.
    $Missing = $null
    $Empty = ''

    [pscustomobject]@{
        MissingFallback = $Missing ?? 'fallback'
        EmptyFallback = $Empty ?? 'fallback'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
