[CmdletBinding()]
param()

try {
    # PowerShell comparisons are case-insensitive by default for strings.
    $DefaultMatch = 'PowerShell' -eq 'powershell'

    # Prefix c makes comparison case-sensitive.
    $CaseSensitiveMatch = 'PowerShell' -ceq 'powershell'

    [pscustomobject]@{
        DefaultMatch = $DefaultMatch
        CaseSensitiveMatch = $CaseSensitiveMatch
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
