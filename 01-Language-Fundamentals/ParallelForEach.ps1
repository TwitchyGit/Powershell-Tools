<#
.SYNOPSIS
Shows parallel pipeline execution.

.DESCRIPTION
The script reports parallel results from local sample input.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # ForEach-Object -Parallel runs script blocks in separate runspaces.
    $Results = 1..4 | ForEach-Object -Parallel {
        [pscustomobject]@{
            Input = $_
            Double = $_ * 2
        }
    } -ThrottleLimit 2

    [pscustomobject]@{
        Stage = 'ParallelForEach'
        InputCount = 4
        ResultCount = $Results.Count
        Results = $Results | Sort-Object -Property Input
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
