[CmdletBinding()]
param()

try {
    # Get-Process emits process objects. Sort-Object can order by numeric properties.
    Get-Process |
        Sort-Object -Property CPU -Descending |
        Select-Object -First 5 -Property ProcessName, Id, CPU

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
