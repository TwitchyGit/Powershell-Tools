[CmdletBinding()]
param()

try {
    # Ordered hashtable preserves insertion order. Normal hashtable does not promise order.
    $Record = [ordered]@{
        First = 'Ada'
        Last = 'Lovelace'
        Topic = 'Computation'
    }

    [pscustomobject]$Record
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
