<#
.SYNOPSIS
Shows the information stream boundary.

.DESCRIPTION
The script reports success output separate from an information message.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Information stream keeps user messages separate from success output.
    Write-Information -MessageData 'Preparing result' -InformationAction Continue

    [pscustomobject]@{
        Stage = 'StreamDemo'
        Result = 'Success output'
        InformationMessage = 'Preparing result'
        StreamBoundary = 'Information is separate from success output'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
