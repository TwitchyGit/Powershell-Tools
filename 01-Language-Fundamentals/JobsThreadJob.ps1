<#
.SYNOPSIS
Shows local thread job execution.

.DESCRIPTION
The script starts a thread job and reports collected result state.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Thread job runs work in same process. Receive-Job collects serialized result.
    $Job = Start-ThreadJob -ScriptBlock {
        [pscustomobject]@{ Value = 21 * 2 }
    }

    $Result = Receive-Job -Job $Job -Wait -AutoRemoveJob
    [pscustomobject]@{
        Stage = 'ThreadJob'
        JobState = $Job.State
        Result = $Result
        Completed = $Result.Value -eq 42
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
