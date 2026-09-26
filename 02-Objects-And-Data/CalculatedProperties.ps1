<#
.SYNOPSIS
Shows calculated report properties.

.DESCRIPTION
The script reports derived size fields without changing source data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Calculated properties reshape objects without changing original data.
    $Rows = @(
        [pscustomobject]@{ Name = 'Alpha'; Bytes = 1536 },
        [pscustomobject]@{ Name = 'Beta'; Bytes = 4096 }
    )

    $Report = $Rows |
        Select-Object -Property Name, @{
            Name = 'Kilobytes'
            Expression = { [math]::Round($_.Bytes / 1KB, 2) }
        }, @{
            Name = 'SizeBand'
            Expression = { if ($_.Bytes -ge 4KB) { 'Large' } else { 'Small' } }
        }

    [pscustomobject]@{
        Stage = 'CalculatedProperties'
        SourceCount = $Rows.Count
        Report = $Report
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
