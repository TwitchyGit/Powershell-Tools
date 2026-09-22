[CmdletBinding()]
param()

try {
    # Date methods return new DateTime values. Original value stays unchanged.
    $Start = Get-Date -Date '2026-01-01T09:00:00'
    $Later = $Start.AddHours(6)
    $Duration = $Later - $Start

    [pscustomobject]@{
        Start = $Start
        Later = $Later
        Hours = $Duration.TotalHours
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
