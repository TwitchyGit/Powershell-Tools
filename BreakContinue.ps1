[CmdletBinding()]
param()

try {
    # continue skips current loop item. break exits loop entirely.
    foreach ($Number in 1..10) {
        if ($Number % 2 -eq 1) {
            continue
        }

        if ($Number -gt 6) {
            break
        }

        $Number
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
