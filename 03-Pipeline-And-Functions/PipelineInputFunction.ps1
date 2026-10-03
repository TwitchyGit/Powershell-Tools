<#
.SYNOPSIS
Shows function input from the pipeline.

.DESCRIPTION
The script reports labelled objects created from pipeline input.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

function ConvertToCourseLabel {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [string]$Name
    )

    process {
        # Process block runs once per pipeline item. Begin and end run once per pipeline.
        [pscustomobject]@{
            OriginalName = $Name
            Label = "Course item: $Name"
        }
    }
}

try {
    $Results = 'Objects', 'Pipeline', 'Errors' | ConvertToCourseLabel
    [pscustomobject]@{
        Stage = 'PipelineInput'
        InputCount = $Results.Count
        Results = $Results
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
