<#
.SYNOPSIS
Shows named configuration output.

.DESCRIPTION
The script writes a local training configuration setting and validates the file.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$Name = 'RunMode',

    [string]$Value = 'Training'
)

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ConfigModule.psm1') -Force -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'NameAndValue'
        Passed = -not [string]::IsNullOrWhiteSpace($Name) -and -not [string]::IsNullOrWhiteSpace($Value)
    }

    $Result = Set-TrainingConfiguration -Name $Name -Value $Value
    $Result

    [pscustomobject]@{
        Stage = 'Validate'
        Check = 'ConfigurationWritten'
        Value = $Result.Path
        Passed = Test-Path -Path $Result.Path -PathType Leaf
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
