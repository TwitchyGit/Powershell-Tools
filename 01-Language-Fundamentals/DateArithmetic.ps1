<#
.SYNOPSIS
Shows DateTime arithmetic.

.DESCRIPTION
The script reports elapsed time and a retention date from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Date methods return new DateTime values. Original value stays unchanged.
    $Start = Get-Date -Date '2026-01-01T09:00:00'
    $Later = $Start.AddHours(6)
    $Duration = $Later - $Start

    [pscustomobject]@{
        Stage = 'DateArithmetic'
        Start = $Start
        Later = $Later
        Hours = $Duration.TotalHours
        RetentionExpires = $Start.AddDays(30)
        IsExpiredOnSampleDate = [datetime]'2026-02-15' -gt $Start.AddDays(30)
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
