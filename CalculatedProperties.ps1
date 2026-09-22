[CmdletBinding()]
param()

try {
    # Calculated properties reshape objects without changing original data.
    $Rows = @(
        [pscustomobject]@{ Name = 'Alpha'; Bytes = 1536 },
        [pscustomobject]@{ Name = 'Beta'; Bytes = 4096 }
    )

    $Rows |
        Select-Object -Property Name, @{
            Name = 'Kilobytes'
            Expression = { [math]::Round($_.Bytes / 1KB, 2) }
        }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
