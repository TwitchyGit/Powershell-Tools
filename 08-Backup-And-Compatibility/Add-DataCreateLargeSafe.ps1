<#
.SYNOPSIS
Shows large safe sample data generation.

.DESCRIPTION
The script writes local safe account data and reports record count.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$SafeName = 'Training-Large-Safe',

    [int]$AccountCount = 25
)

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-user-backup'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'SafeInput'
        SafeName = $SafeName
        AccountCount = $AccountCount
        Passed = -not [string]::IsNullOrWhiteSpace($SafeName) -and $AccountCount -gt 0
    }

    $Accounts = for ($Index = 1; $Index -le $AccountCount; $Index++) {
        [pscustomobject]@{
            SafeName = $SafeName
            AccountName = 'training-account-{0:000}' -f $Index
            PlatformId = 'Training-Platform'
            Address = 'training-host-{0:000}' -f $Index
        }
    }

    $SafePath = Join-Path -Path $DataFolder -ChildPath 'large-safe-data.json'
    ConvertTo-Json -InputObject $Accounts -Depth 4 |
        Set-Content -Path $SafePath -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'CreateLargeSafeData'
        SafeName = $SafeName
        AccountCount = $AccountCount
        SafePath = $SafePath
        EstimatedRecordCount = $Accounts.Count
        Exists = Test-Path -Path $SafePath -PathType Leaf
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
