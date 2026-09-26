<#
.SYNOPSIS
Shows parameter validation.

.DESCRIPTION
The script reports accepted input and allowed values.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [ValidateSet('Beginner', 'Intermediate', 'Advanced')]
    [string]$Level = 'Beginner'
)

try {
    # ValidateSet rejects unsupported input before script body runs.
    [pscustomobject]@{
        Stage = 'ParameterValidation'
        Level = $Level
        Accepted = $true
        AllowedValues = @('Beginner', 'Intermediate', 'Advanced')
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
