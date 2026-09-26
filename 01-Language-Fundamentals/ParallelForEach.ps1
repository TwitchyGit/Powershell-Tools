[CmdletBinding()]
param()

try {
    # ForEach-Object -Parallel runs script blocks in separate runspaces.
    1..4 | ForEach-Object -Parallel {
        [pscustomobject]@{
            Input = $_
            Double = $_ * 2
        }
    } -ThrottleLimit 2

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
