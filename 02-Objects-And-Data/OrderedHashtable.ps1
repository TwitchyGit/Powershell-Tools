<#
.SYNOPSIS
Shows ordered property output.

.DESCRIPTION
The script reports insertion order and an object created from ordered data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Ordered hashtable preserves insertion order. Normal hashtable does not promise order.
    $Record = [ordered]@{
        First = 'Ada'
        Last = 'Lovelace'
        Topic = 'Computation'
    }

    [pscustomobject]@{
        Stage = 'OrderedHashtable'
        PropertyOrder = $Record.Keys
        Record = [pscustomobject]$Record
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
