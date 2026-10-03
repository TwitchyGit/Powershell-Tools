[CmdletBinding()]
param()

try {
    # Get-ChildItem returns rich FileInfo and DirectoryInfo objects not plain path text.
    $Items = Get-ChildItem -Path $PWD -File -ErrorAction Stop |
        Select-Object -First 5 -Property Name, Length, Extension

    $Items
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
