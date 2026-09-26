<#
.SYNOPSIS
Shows pipeline begin, process and end blocks.

.DESCRIPTION
The script reports a pipeline summary from numeric input.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

function MeasureCourseInput {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [int]$Number
    )

    begin {
        # Begin runs once before pipeline input. Use it to prepare shared state.
        $Total = 0
        $Count = 0
        $Seen = @()
    }

    process {
        # Process runs once per input item. Use it for per-object work.
        $Total += $Number
        $Count++
        $Seen += $Number
    }

    end {
        # End runs once after input ends. Use it to emit final result.
        [pscustomobject]@{
            Stage = 'PipelineSummary'
            Count = $Count
            Total = $Total
            Average = if ($Count -gt 0) { $Total / $Count } else { 0 }
            InputSeen = $Seen
        }
    }
}

try {
    $Result = 1..5 | MeasureCourseInput
    $Result
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
