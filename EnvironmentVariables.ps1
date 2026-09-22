[CmdletBinding()]
param()

try {
    # Env: exposes process environment variables through a provider.
    [pscustomobject]@{
        TempPath = $env:TEMP
        Shell = $env:SHELL
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
