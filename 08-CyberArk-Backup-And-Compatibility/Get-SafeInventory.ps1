<#
.SYNOPSIS
Shows safe inventory output.

.DESCRIPTION
The script writes local inventory data and reports restore counts.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-airgap-restore'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Inventory = @(
        [pscustomobject]@{
            SafeName = 'Training-App-Safe'
            AccountCount = 4
            RestoreRequired = $true
            Classification = 'Application'
        }
        [pscustomobject]@{
            SafeName = 'Training-DB-Safe'
            AccountCount = 2
            RestoreRequired = $true
            Classification = 'Database'
        }
        [pscustomobject]@{
            SafeName = 'Training-Archive-Safe'
            AccountCount = 0
            RestoreRequired = $false
            Classification = 'Archive'
        }
    )

    $InventoryPath = Join-Path -Path $DataFolder -ChildPath 'safe-inventory.json'
    ConvertTo-Json -InputObject $Inventory -Depth 4 |
        Set-Content -Path $InventoryPath -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'InventorySummary'
        InventoryPath = $InventoryPath
        SafeCount = $Inventory.Count
        RestoreRequiredCount = ($Inventory | Where-Object { $_.RestoreRequired }).Count
        TotalAccounts = ($Inventory | Measure-Object -Property AccountCount -Sum).Sum
        Safes = $Inventory
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
