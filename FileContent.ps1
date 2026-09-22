[CmdletBinding()]
param()

try {
    # Set-Content writes text. Get-Content reads one line per output object by default.
    $TempPath = [System.IO.Path]::GetTempPath()
    $Path = Join-Path -Path $TempPath -ChildPath 'powershell-course-content.txt'
    Set-Content -Path $Path -Value @('alpha', 'beta')

    Get-Content -Path $Path | ForEach-Object {
        "Line: $_"
    }

    Remove-Item -Path $Path -ErrorAction SilentlyContinue
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
