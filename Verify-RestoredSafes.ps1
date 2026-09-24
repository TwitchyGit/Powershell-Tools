[CmdletBinding()]
param()

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-airgap-restore'
    $InventoryPath = Join-Path -Path $DataFolder -ChildPath 'safe-inventory.json'

    if (-not (Test-Path -Path $InventoryPath -PathType Leaf)) {
        Write-Error -Message 'Safe inventory sample was not found. Run Get-SafeInventory.ps1 first.' -ErrorAction Stop
    }

    $Inventory = Get-Content -Path $InventoryPath -Raw -ErrorAction Stop | ConvertFrom-Json
    foreach ($Safe in $Inventory) {
        [pscustomobject]@{
            SafeName = $Safe.SafeName
            ExpectedAccounts = $Safe.AccountCount
            RestoreRequired = $Safe.RestoreRequired
            Verification = if ($Safe.RestoreRequired) { 'WouldVerifyRestoredSafe' } else { 'SkippedNoRestoreRequired' }
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
