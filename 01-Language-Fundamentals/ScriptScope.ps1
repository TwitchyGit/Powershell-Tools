<#
.SYNOPSIS
Shows script-scoped state.

.DESCRIPTION
The script reports a counter shared by functions inside this file.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
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
    [pscustomobject]@{
        Stage = 'ScriptScope'
        Counter = $script:Counter
        Scope = 'Script'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
