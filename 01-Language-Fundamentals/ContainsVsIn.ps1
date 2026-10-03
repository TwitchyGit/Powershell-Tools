<#
.SYNOPSIS
Shows collection membership checks.

.DESCRIPTION
The script compares collection-first and value-first membership syntax from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # -contains reads collection first. -in reads candidate first. They test same membership relation.
    $Values = 'red', 'green', 'blue'

    [pscustomobject]@{
        Stage = 'ContainsVsIn'
        Values = $Values
        ContainsGreen = $Values -contains 'green'
        GreenInValues = 'green' -in $Values
        YellowAllowed = 'yellow' -in $Values
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
