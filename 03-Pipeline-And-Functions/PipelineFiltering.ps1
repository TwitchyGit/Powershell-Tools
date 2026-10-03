<#
.SYNOPSIS
Shows pipeline filtering.

.DESCRIPTION
The script reports kept and dropped counts from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Where-Object keeps objects where script block returns true.
    $Source = 1..10
    $Results = $Source | Where-Object {
        $_ % 2 -eq 0
    }

    [pscustomobject]@{
        Stage = 'FilterPipeline'
        SourceCount = $Source.Count
        EvenNumbers = $Results -join ', '
        Count = $Results.Count
        DroppedCount = $Source.Count - $Results.Count
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
