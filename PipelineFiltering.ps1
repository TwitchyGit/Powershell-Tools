[CmdletBinding()]
param()

try {
    # Where-Object keeps objects where script block returns true.
    $Results = 1..10 | Where-Object {
        $_ % 2 -eq 0
    }

    [pscustomobject]@{
        EvenNumbers = $Results -join ', '
        Count = $Results.Count
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
