<#
.SYNOPSIS
Shows grouping and sorting of objects.

.DESCRIPTION
The script reports group counts from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Group-Object collects objects by property value. Sort-Object orders resulting groups.
    $Data = @(
        [pscustomobject]@{ Name = 'A'; Type = 'Script' },
        [pscustomobject]@{ Name = 'B'; Type = 'Module' },
        [pscustomobject]@{ Name = 'C'; Type = 'Script' }
    )

    $Groups = $Data |
        Group-Object -Property Type |
        Sort-Object -Property Count -Descending |
        Select-Object -Property Name, Count

    [pscustomobject]@{
        Stage = 'GroupAndSort'
        SourceCount = $Data.Count
        GroupCount = $Groups.Count
        Groups = $Groups
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
