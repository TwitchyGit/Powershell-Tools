[CmdletBinding()]
param()

try {
    # do-until runs at least once. Test happens after body.
    $Count = 0

    do {
        $Count++
        $Count
    } until ($Count -eq 3)

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
