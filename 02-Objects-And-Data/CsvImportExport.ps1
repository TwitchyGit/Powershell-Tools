<#
.SYNOPSIS
Shows CSV import and export shape.

.DESCRIPTION
The script writes a temporary CSV, imports it and reports typed rows.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # CSV stores text. Type information is lost unless you convert values after import.
    $TempPath = [System.IO.Path]::GetTempPath()
    $Path = Join-Path -Path $TempPath -ChildPath 'powershell-course-demo.csv'
    $Data = @(
        [pscustomobject]@{ Name = 'Example'; Count = 3 },
        [pscustomobject]@{ Name = 'Second'; Count = 5 }
    )

    $Data | Export-Csv -Path $Path -NoTypeInformation
    $Imported = Import-Csv -Path $Path
    $RequiredColumns = @('Name', 'Count')
    $MissingColumns = $RequiredColumns |
        Where-Object { $_ -notin $Imported[0].PSObject.Properties.Name }
    $TypedRows = $Imported | ForEach-Object {
        [pscustomobject]@{
            Name = $_.Name
            Count = [int]$_.Count
        }
    }

    [pscustomobject]@{
        Stage = 'CsvRoundTrip'
        Path = $Path
        RowCount = $TypedRows.Count
        MissingColumns = $MissingColumns
        CountTypeBeforeCast = $Imported[0].Count.GetType().Name
        TypedRows = $TypedRows
    }

    Remove-Item -Path $Path -ErrorAction SilentlyContinue
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
