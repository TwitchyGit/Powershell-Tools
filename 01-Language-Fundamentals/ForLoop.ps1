<#
.SYNOPSIS
Shows indexed loop processing.

.DESCRIPTION
The script reports item index values and attempt numbers from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # for loop is useful when index value matters.
    $Names = 'Alpha', 'Beta', 'Gamma'
    $Rows = for ($Index = 0; $Index -lt $Names.Count; $Index++) {
        [pscustomobject]@{
            Index = $Index
            Name = $Names[$Index]
            AttemptNumber = $Index + 1
        }
    }

    [pscustomobject]@{
        Stage = 'ForLoop'
        ItemCount = $Rows.Count
        Rows = $Rows
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
