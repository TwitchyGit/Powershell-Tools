<#
.SYNOPSIS
Shows fixed named states with an enum.

.DESCRIPTION
The script reports enum value, numeric value and allowed state names.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

enum CourseState {
    Draft
    Ready
    Archived
}

try {
    # Enum constrains values to named constants. This avoids magic strings.
    [CourseState]$State = 'Ready'

    [pscustomobject]@{
        Stage = 'EnumDefinition'
        State = $State
        NumericValue = [int]$State
        AllowedStates = [CourseState].GetEnumNames()
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
