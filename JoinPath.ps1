[CmdletBinding()]
param()

try {
    # Join-Path uses provider rules. Avoid manual slash handling.
    $TempPath = [System.IO.Path]::GetTempPath()
    $Path = Join-Path -Path $TempPath -ChildPath 'course' -AdditionalChildPath 'sample.txt'

    [pscustomobject]@{
        Path = $Path
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
