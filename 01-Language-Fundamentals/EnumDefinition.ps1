[CmdletBinding()]
param()

enum CourseState {
    Draft
    Ready
    Archived
}

try {
    # Enum constrains values to named constants. This avoids magic strings.
    [CourseState]$State = 'Ready'

    [pscustomobject]@{
        State = $State
        NumericValue = [int]$State
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
