<#
.SYNOPSIS
Shows ordered array access by index.

.DESCRIPTION
The script reports first item, last item and a selected index from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Arrays preserve order. Index zero is first item because PowerShell uses .NET collection indexing.
    $Names = @('Ada', 'Grace', 'Edsger')

    # Negative indexes count from end. This is PowerShell syntax over normal collection access.
    $FirstName = $Names[0]
    $LastName = $Names[-1]

    [pscustomobject]@{
        Stage = 'ArrayIndexing'
        First = $FirstName
        Last = $LastName
        Count = $Names.Count
        TargetIndex = 1
        TargetValue = $Names[1]
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
