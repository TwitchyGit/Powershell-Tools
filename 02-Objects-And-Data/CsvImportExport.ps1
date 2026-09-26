[CmdletBinding()]
param()

try {
    # CSV stores text. Type information is lost unless you convert values after import.
    $TempPath = [System.IO.Path]::GetTempPath()
    $Path = Join-Path -Path $TempPath -ChildPath 'powershell-course-demo.csv'
    $Data = [pscustomobject]@{ Name = 'Example'; Count = 3 }

    $Data | Export-Csv -Path $Path -NoTypeInformation
    $Imported = Import-Csv -Path $Path

    [pscustomobject]@{
        Name = $Imported.Name
        CountText = $Imported.Count
        CountType = $Imported.Count.GetType().Name
    }

    Remove-Item -Path $Path -ErrorAction SilentlyContinue
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
