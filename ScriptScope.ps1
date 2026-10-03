[CmdletBinding()]
param()

$script:Counter = 0

function AddCourseCount {
    [CmdletBinding()]
    param()

    # Script scope lets functions in this file share state without using global state.
    $script:Counter++
}

try {
    AddCourseCount
    AddCourseCount
    $script:Counter

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
