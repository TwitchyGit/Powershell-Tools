[CmdletBinding()]
param()

try {
    # PSDefaultParameterValues supplies defaults without changing command calls.
    $PSDefaultParameterValues['Select-Object:First'] = 2

    1..5 | Select-Object

    $PSDefaultParameterValues.Remove('Select-Object:First')
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
