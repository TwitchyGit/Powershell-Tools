<#
.SYNOPSIS
Provides local configuration training functions.

.DESCRIPTION
The module returns sample settings and writes local configuration records.

.NOTES
This module is training material. It uses local sample data unless a caller supplies another path.
#>
function Get-TrainingConfiguration {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        GroupName = 'Training-Operators'
        RunFileName = 'autosys-training.run'
        TargetOu = 'OU=Training,DC=example,DC=invalid'
        PasPlatformId = 'Training-Windows'
        OutputFolder = '.sample-training-data'
    }
}

function Set-TrainingConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Value
    )

    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-training-data'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Path = Join-Path -Path $DataFolder -ChildPath 'training-configuration.json'
    $Record = [pscustomobject]@{
        Name = $Name
        Value = $Value
        SavedAt = (Get-Date -Format o)
    }

    $Record |
        ConvertTo-Json -Depth 4 |
        Set-Content -Path $Path -ErrorAction Stop

    [pscustomobject]@{
        Name = $Record.Name
        Value = $Record.Value
        Path = $Path
    }
}

Export-ModuleMember -Function Get-TrainingConfiguration
Export-ModuleMember -Function Set-TrainingConfiguration
