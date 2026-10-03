<#
.SYNOPSIS
Shows terminating error handling.

.DESCRIPTION
The script reports a handled missing-file error.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Non-terminating errors do not enter catch unless ErrorAction Stop converts them.
    Get-Item -Path '__missing_file__' -ErrorAction Stop | Out-Null

    exit 0
} catch {
    [pscustomobject]@{
        Stage = 'HandledError'
        Handled = $true
        ErrorType = $_.Exception.GetType().Name
        Message = $_.Exception.Message
        NextAction = 'Report and continue in this training sample'
    }

    exit 0
}
