[CmdletBinding()]
param()

try {
    $FailedObjects = @(
        [pscustomobject]@{
            Name = 'training-safe-03'
            Reason = 'MissingPlatform'
            RetryAction = 'ReviewTrainingData'
        }
        [pscustomobject]@{
            Name = 'training-safe-04'
            Reason = 'DuplicateName'
            RetryAction = 'RenameTrainingObject'
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

    $FailedObjects

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
