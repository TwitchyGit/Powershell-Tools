<#
.SYNOPSIS
Shows loop skip and stop control.

.DESCRIPTION
The script reports processed items, skipped items and the stop condition from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # continue skips current loop item. break exits loop entirely.
    $Processed = @()
    $Skipped = @()
    foreach ($Number in 1..10) {
        if ($Number % 2 -eq 1) {
            $Skipped += $Number
            continue
        }

        if ($Number -gt 6) {
            break
        }

        $Processed += $Number
    }

    [pscustomobject]@{
        Stage = 'BreakContinue'
        Processed = $Processed
        Skipped = $Skipped
        StopReason = 'FirstEvenNumberGreaterThanSix'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
