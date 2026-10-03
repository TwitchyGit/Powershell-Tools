<#
.SYNOPSIS
Shows the boundary between data and display formatting.

.DESCRIPTION
The script reports object output type and formatting instruction type.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Format-* creates display instructions. Use Select-Object when later code needs data.
    $Object = [pscustomobject]@{ Name = 'Sample'; Count = 7 }
    $Selected = $Object | Select-Object -Property Name
    $Formatted = $Object | Format-Table -Property Name

    [pscustomobject]@{
        Stage = 'FormatBoundary'
        SelectedType = $Selected.GetType().Name
        FormattedType = $Formatted[0].GetType().Name
        SelectedStillHasName = $null -ne $Selected.PSObject.Properties['Name']
        FormattedIsDisplayInstruction = $Formatted[0].GetType().Name -like 'Format*'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
