<#
.SYNOPSIS
Shows file discovery as objects.

.DESCRIPTION
The script reports a sample of files from this unit folder.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Get-ChildItem returns rich FileInfo and DirectoryInfo objects not plain path text.
    $Items = Get-ChildItem -Path $PSScriptRoot -File -ErrorAction Stop |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 5 -Property Name, Length, Extension, LastWriteTime

    [pscustomobject]@{
        Stage = 'FileDiscovery'
        SearchPath = $PSScriptRoot
        FileCountSampled = $Items.Count
        TotalBytes = ($Items | Measure-Object -Property Length -Sum).Sum
        Items = $Items
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
