<#
.SYNOPSIS
Shows scoped default parameter values.

.DESCRIPTION
The script reports selected values and restores prior defaults.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # PSDefaultParameterValues supplies defaults without changing command calls.
    $OriginalDefaults = @{} + $PSDefaultParameterValues
    $PSDefaultParameterValues['Select-Object:First'] = 2

    $Selected = 1..5 | Select-Object

    [pscustomobject]@{
        Stage = 'DefaultParameterValue'
        DefaultKey = 'Select-Object:First'
        SelectedCount = @($Selected).Count
        SelectedValues = $Selected
    }

    $PSDefaultParameterValues.Remove('Select-Object:First')
    foreach ($Key in $OriginalDefaults.Keys) {
        $PSDefaultParameterValues[$Key] = $OriginalDefaults[$Key]
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
