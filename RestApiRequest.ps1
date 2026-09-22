[CmdletBinding()]
param()

try {
    # Invoke-RestMethod converts JSON response bodies into PowerShell objects.
    $Uri = 'https://example.invalid/api/course'

    [pscustomobject]@{
        Uri = $Uri
        DemoOnly = $true
        Reason = 'Use Invoke-RestMethod for real HTTP APIs'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
