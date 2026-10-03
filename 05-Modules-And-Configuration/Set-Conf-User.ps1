<#
.SYNOPSIS
Shows user configuration output.

.DESCRIPTION
The script writes a local user configuration record and reports file state.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$UserName = 'training.user'
)

try {
    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'UserName'
        Value = $UserName
        Passed = -not [string]::IsNullOrWhiteSpace($UserName)
    }

    $Record = [pscustomobject]@{
        UserName = $UserName
        Role = 'TrainingOperator'
        Enabled = $true
        Source = 'CourseSample'
        SavedAt = (Get-Date -Format o)
    }

    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-training-data'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Path = Join-Path -Path $DataFolder -ChildPath 'training-user-configuration.json'
    $Record |
        ConvertTo-Json -Depth 4 |
        Set-Content -Path $Path -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'SetUserConfiguration'
        UserName = $Record.UserName
        Role = $Record.Role
        Path = $Path
        Exists = Test-Path -Path $Path -PathType Leaf
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
