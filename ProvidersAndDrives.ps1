[CmdletBinding()]
param()

try {
    # Providers expose different data stores through path syntax.
    Get-PSDrive |
        Select-Object -First 5 -Property Name, Provider, Root

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
