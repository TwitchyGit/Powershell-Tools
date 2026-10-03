<#
.SYNOPSIS
Shows environment-variable secret handling boundaries.

.DESCRIPTION
The script stores a synthetic secret in the process environment and removes it before exit.

.NOTES
Environment variables are process state. They are not a secure vault or audit boundary.
#>
[CmdletBinding()]
param()

try {
    $VariableName = 'TRAINING_SECRET_SAMPLE'
    [System.Environment]::SetEnvironmentVariable($VariableName, 'SyntheticToken-DoNotUse', 'Process')
    $StoredValue = [System.Environment]::GetEnvironmentVariable($VariableName, 'Process')
    [System.Environment]::SetEnvironmentVariable($VariableName, $null, 'Process')
    $RemovedValue = [System.Environment]::GetEnvironmentVariable($VariableName, 'Process')

    [pscustomobject]@{
        VariableName = $VariableName
        Scope = 'Process'
        WasReadable = -not [string]::IsNullOrWhiteSpace($StoredValue)
        RemovedBeforeExit = [string]::IsNullOrWhiteSpace($RemovedValue)
        SafeUse = 'Short-lived child process input'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
