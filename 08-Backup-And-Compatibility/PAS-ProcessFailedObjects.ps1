<#
.SYNOPSIS
Shows failed object classification.

.DESCRIPTION
The script writes local failed-object data and reports retry eligibility.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $FailedObjects = @(
        [pscustomobject]@{
            Name = 'training-safe-03'
            Reason = 'MissingPlatform'
            RetryAction = 'ReviewTrainingData'
            RetryEligible = $true
        }
        [pscustomobject]@{
            Name = 'training-safe-04'
            Reason = 'DuplicateName'
            RetryAction = 'RenameTrainingObject'
            RetryEligible = $true
        }
    )

    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-training-data'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Path = Join-Path -Path $DataFolder -ChildPath 'pas-failed-objects.json'
    $FailedObjects |
        ConvertTo-Json -Depth 4 |
        Set-Content -Path $Path -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'ProcessFailedObjects'
        FailedCount = $FailedObjects.Count
        RetryEligibleCount = ($FailedObjects | Where-Object { $_.RetryEligible }).Count
        Path = $Path
        FailedObjects = $FailedObjects
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
