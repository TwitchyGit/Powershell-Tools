<#
.SYNOPSIS
Shows restore inventory verification.

.DESCRIPTION
The script reads local safe inventory and reports per-safe verification state.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-airgap-restore'
    $InventoryPath = Join-Path -Path $DataFolder -ChildPath 'safe-inventory.json'

    if (-not (Test-Path -Path $InventoryPath -PathType Leaf)) {
        Write-Error -Message 'Safe inventory sample was not found. Run Get-SafeInventory.ps1 first.' -ErrorAction Stop
    }

    $Inventory = Get-Content -Path $InventoryPath -Raw -ErrorAction Stop | ConvertFrom-Json
    $Results = foreach ($Safe in $Inventory) {
        $Verification = if ($Safe.RestoreRequired) { 'WouldVerifyRestoredSafe' } else { 'SkippedNoRestoreRequired' }
        $Passed = -not $Safe.RestoreRequired -or $Safe.AccountCount -gt 0

        [pscustomobject]@{
            SafeName = $Safe.SafeName
            ExpectedAccounts = $Safe.AccountCount
            RestoreRequired = $Safe.RestoreRequired
            Verification = $Verification
            Passed = $Passed
        }
    }

    [pscustomobject]@{
        Stage = 'VerifyRestore'
        CheckedSafes = $Results.Count
        FailedSafes = ($Results | Where-Object { -not $_.Passed }).Count
        Results = $Results
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
