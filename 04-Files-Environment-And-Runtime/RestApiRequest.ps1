<#
.SYNOPSIS
Shows REST request shape without a live call.

.DESCRIPTION
The script reports request metadata and a mock response object.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Invoke-RestMethod converts JSON response bodies into PowerShell objects.
    $Uri = 'https://example.invalid/api/course'
    $Headers = @{
        Accept = 'application/json'
        'X-Training-Mode' = 'true'
    }
    $MockResponse = [pscustomobject]@{
        Id = 101
        Name = 'TrainingApiResult'
        Status = 'Ready'
    }

    [pscustomobject]@{
        Stage = 'RestRequestShape'
        Uri = $Uri
        Method = 'GET'
        TimeoutSeconds = 30
        HeaderCount = $Headers.Count
        MockResponse = $MockResponse
        DemoOnly = $true
        Reason = 'Use Invoke-RestMethod for real HTTP APIs'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
