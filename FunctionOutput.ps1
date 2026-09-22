[CmdletBinding()]
param()

function GetCourseValue {
    [CmdletBinding()]
    param(
        [int]$Number
    )

    # PowerShell outputs uncaptured expression results. Return is for control flow.
    $Number * 2
}

try {
    GetCourseValue -Number 21
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
