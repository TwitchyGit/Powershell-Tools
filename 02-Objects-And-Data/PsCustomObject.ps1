<#
.SYNOPSIS
Shows custom object report rows.

.DESCRIPTION
The script reports property count and selected report fields.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # PSCustomObject creates predictable named properties for pipeline processing.
    $Item = [pscustomobject]@{
        Name = 'Pipeline'
        Category = 'Core'
        Level = 2
    }

    [pscustomobject]@{
        Stage = 'CreateReportRow'
        PropertyCount = $Item.PSObject.Properties.Count
        ReportRow = $Item | Select-Object -Property Name, Level
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
