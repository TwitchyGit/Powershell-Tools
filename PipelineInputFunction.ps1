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
        "Course item: $Name"
    }
}

try {
    'Objects', 'Pipeline', 'Errors' | ConvertToCourseLabel
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
