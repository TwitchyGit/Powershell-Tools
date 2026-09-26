<#
.SYNOPSIS
Shows a post-test polling loop.

.DESCRIPTION
The script reports loop attempts and final condition state from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # do-until runs at least once. Test happens after body.
    $Count = 0
    $Attempts = @()

    do {
        $Count++
        $Attempts += $Count
    } until ($Count -eq 3)

    [pscustomobject]@{
        Stage = 'DoUntil'
        Attempts = $Attempts
        FinalCount = $Count
        ConditionMet = $Count -eq 3
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
