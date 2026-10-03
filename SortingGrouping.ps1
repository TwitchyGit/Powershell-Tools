[CmdletBinding()]
param()

try {
    # Group-Object collects objects by property value. Sort-Object orders resulting groups.
    $Data = @(
        [pscustomobject]@{ Name = 'A'; Type = 'Script' },
        [pscustomobject]@{ Name = 'B'; Type = 'Module' },
        [pscustomobject]@{ Name = 'C'; Type = 'Script' }
    )

    $Data |
        Group-Object -Property Type |
        Sort-Object -Property Count -Descending |
        Select-Object -Property Name, Count

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
