<#
.SYNOPSIS
Shows array slicing with range indexes.

.DESCRIPTION
The script reports middle items, reversed items and a final page from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Range operator creates integer indexes. PowerShell returns matching elements in same order.
    $Numbers = 10, 20, 30, 40, 50
    $Middle = $Numbers[1..3]

    # Reversed ranges work too. Result order follows range order not original array order.
    $Reverse = $Numbers[3..1]

    [pscustomobject]@{
        Stage = 'ArraySlicing'
        SourceCount = $Numbers.Count
        Middle = $Middle -join ', '
        Reverse = $Reverse -join ', '
        FinalPage = ($Numbers[4..4] -join ', ')
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
