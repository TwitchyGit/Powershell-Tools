[CmdletBinding()]
param()

try {
    # Information stream keeps user messages separate from success output.
    Write-Information -MessageData 'Preparing result' -InformationAction Continue

    [pscustomobject]@{
        Result = 'Success output'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
