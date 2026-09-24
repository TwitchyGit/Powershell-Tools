[CmdletBinding()]
param(
    [string]$JobName = 'TRAINING_DEPLOYMENT_JOB'
)

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-training-data'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $RunFilePath = Join-Path -Path $DataFolder -ChildPath 'autosys-training.run'
    $RunFile = @(
        'insert_job: {0}' -f $JobName
        'job_type: CMD'
        'command: powershell -File Deploy-GitRepository.ps1'
        'machine: training-host'
        'owner: training.user'
        'permission: gx,ge'
    )

    Set-Content -Path $RunFilePath -Value $RunFile -ErrorAction Stop

    [pscustomobject]@{
        JobName = $JobName
        RunFilePath = $RunFilePath
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
