[CmdletBinding()]
param()

try {
    # Non-terminating errors do not enter catch unless ErrorAction Stop converts them.
    Get-Item -Path '__missing_file__' -ErrorAction Stop | Out-Null

    exit 0
} catch {
    [pscustomobject]@{
        Handled = $true
        ErrorType = $_.Exception.GetType().Name
        Message = $_.Exception.Message
    }

    exit 0
}
