[CmdletBinding()]
param()

try {
    # PSCustomObject creates predictable named properties for pipeline processing.
    $Item = [pscustomobject]@{
        Name = 'Pipeline'
        Category = 'Core'
        Level = 2
    }

    $Item | Select-Object -Property Name, Level
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
