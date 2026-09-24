[CmdletBinding()]
param(
    [string]$BackupName = 'TrainingDailyBackup'
)

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-user-backup'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Receipt = [pscustomobject]@{
        BackupName = $BackupName
        Schedule = 'Daily'
        IncludesSafes = $true
        IncludesReports = $false
        CompletedAt = (Get-Date -Format o)
        TrainingOnly = $true
    }

    $ReceiptPath = Join-Path -Path $DataFolder -ChildPath 'daily-backup-receipt.json'
    ConvertTo-Json -InputObject $Receipt -Depth 4 |
        Set-Content -Path $ReceiptPath -ErrorAction Stop

    $Receipt

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
