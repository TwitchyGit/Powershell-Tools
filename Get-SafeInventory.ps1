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
        }
        [pscustomobject]@{
            SafeName = 'Training-DB-Safe'
            AccountCount = 2
            RestoreRequired = $true
        }
        [pscustomobject]@{
            SafeName = 'Training-Archive-Safe'
            AccountCount = 0
            RestoreRequired = $false
        }
    )

    $InventoryPath = Join-Path -Path $DataFolder -ChildPath 'safe-inventory.json'
    ConvertTo-Json -InputObject $Inventory -Depth 4 |
        Set-Content -Path $InventoryPath -ErrorAction Stop

    $Inventory

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
