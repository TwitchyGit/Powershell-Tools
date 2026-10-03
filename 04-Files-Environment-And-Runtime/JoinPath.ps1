<#
.SYNOPSIS
Shows provider-aware path construction.

.DESCRIPTION
The script reports Join-Path output and a manual path example.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Join-Path uses provider rules. Avoid manual slash handling.
    $TempPath = [System.IO.Path]::GetTempPath()
    $Path = Join-Path -Path $TempPath -ChildPath 'course' -AdditionalChildPath 'sample.txt'
    $ManualPath = '{0}/course/sample.txt' -f $TempPath.TrimEnd('/', '\')

    [pscustomobject]@{
        Stage = 'BuildPortablePath'
        TempPath = $TempPath
        ProviderAwarePath = $Path
        ManualPathExample = $ManualPath
        SameTextOnThisHost = $Path -eq $ManualPath
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
