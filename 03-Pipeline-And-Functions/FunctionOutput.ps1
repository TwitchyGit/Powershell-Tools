<#
.SYNOPSIS
Shows success output from a function.

.DESCRIPTION
The script reports a function output value and type.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

function GetCourseValue {
    [CmdletBinding()]
    param(
        [int]$Number
    )

    # PowerShell outputs uncaptured expression results. Return is for control flow.
    $Number * 2
}

try {
    $Value = GetCourseValue -Number 21
    [pscustomobject]@{
        Stage = 'FunctionOutput'
        Input = 21
        Output = $Value
        OutputType = $Value.GetType().Name
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
