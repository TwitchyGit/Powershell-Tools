<#
.SYNOPSIS
Shows streaming pipeline processing.

.DESCRIPTION
The script reports per-item results and summary counts.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # ForEach-Object runs once per pipeline input object. Current object is $_.
    $Results = 1..5 | ForEach-Object {
        [pscustomobject]@{
            Input = $_
            Square = $_ * $_
            IsEven = $_ % 2 -eq 0
        }
    }

    [pscustomobject]@{
        Stage = 'ForEachObject'
        InputCount = $Results.Count
        EvenCount = ($Results | Where-Object { $_.IsEven }).Count
        Results = $Results
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
