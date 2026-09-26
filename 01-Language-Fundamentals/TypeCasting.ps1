<#
.SYNOPSIS
Shows explicit value conversion.

.DESCRIPTION
The script reports converted values and resulting type names.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Casts convert values before assignment. Failed conversion becomes a terminating error.
    [int]$Count = '42'
    [datetime]$Date = '2026-09-22'

    [pscustomobject]@{
        Stage = 'TypeCasting'
        Count = $Count
        CountType = $Count.GetType().Name
        Date = $Date.ToString('yyyy-MM-dd')
        DateType = $Date.GetType().Name
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
