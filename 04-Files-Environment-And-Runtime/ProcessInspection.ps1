<#
.SYNOPSIS
Shows read-only process inspection.

.DESCRIPTION
The script reports process object data without changing the host.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Get-Process emits process objects. Sort-Object can order by numeric properties.
    $Processes = Get-Process |
        Sort-Object -Property CPU -Descending |
        Select-Object -First 5 -Property ProcessName, Id, CPU

    [pscustomobject]@{
        Stage = 'InspectProcesses'
        SampleCount = $Processes.Count
        HighestCpuProcess = $Processes[0].ProcessName
        Processes = $Processes
        ReadOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
