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
    }

    process {
        # Process runs once per input item. Use it for per-object work.
        $Total += $Number
    }

    end {
        # End runs once after input ends. Use it to emit final result.
        $Total
    }
}

try {
    1..5 | MeasureCourseInput
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
