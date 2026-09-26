[CmdletBinding()]
param()

try {
    # Casts convert values before assignment. Failed conversion becomes a terminating error.
    [int]$Count = '42'
    [datetime]$Date = '2026-09-22'

    [pscustomobject]@{
        Count = $Count
        CountType = $Count.GetType().Name
        Date = $Date.ToString('yyyy-MM-dd')
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
