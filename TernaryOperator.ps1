[CmdletBinding()]
param()

try {
    # Ternary operator chooses one expression. It is best for short decisions.
    $Count = 3
    $Status = $Count -gt 0 ? 'Has items' : 'Empty'

    [pscustomobject]@{
        Count = $Count
        Status = $Status
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
