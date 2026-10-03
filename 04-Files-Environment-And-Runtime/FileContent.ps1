<#
.SYNOPSIS
Shows temporary file content handling.

.DESCRIPTION
The script writes, reads and removes a temporary training file.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Set-Content writes text. Get-Content reads one line per output object by default.
    $TempPath = [System.IO.Path]::GetTempPath()
    $Path = Join-Path -Path $TempPath -ChildPath 'powershell-course-content.txt'
    $Lines = @('alpha', 'beta')
    Set-Content -Path $Path -Value $Lines -Encoding utf8

    Add-Content -Path $Path -Value 'gamma' -Encoding utf8
    $ReadLines = Get-Content -Path $Path -ErrorAction Stop
    $RawContent = Get-Content -Path $Path -Raw -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'FileContentRoundTrip'
        Path = $Path
        LineCount = $ReadLines.Count
        RawLength = $RawContent.Length
        FirstLine = $ReadLines[0]
        ExistsBeforeCleanup = Test-Path -Path $Path -PathType Leaf
    }

    Remove-Item -Path $Path -ErrorAction SilentlyContinue
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
