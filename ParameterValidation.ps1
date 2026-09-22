[CmdletBinding()]
param(
    [ValidateSet('Beginner', 'Intermediate', 'Advanced')]
    [string]$Level = 'Beginner'
)

try {
    # ValidateSet rejects unsupported input before script body runs.
    [pscustomobject]@{
        Level = $Level
        Accepted = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
