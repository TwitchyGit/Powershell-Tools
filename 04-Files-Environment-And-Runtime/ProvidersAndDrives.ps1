<#
.SYNOPSIS
Shows PowerShell providers and drives.

.DESCRIPTION
The script reports a sample of drive and provider metadata.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Providers expose different data stores through path syntax.
    $Drives = Get-PSDrive |
        Select-Object -First 5 -Property Name, Provider, Root

    [pscustomobject]@{
        Stage = 'InspectProviders'
        DriveCountSampled = $Drives.Count
        Providers = $Drives.Provider.Name | Sort-Object -Unique
        Drives = $Drives
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
