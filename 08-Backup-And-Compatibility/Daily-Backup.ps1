<#
.SYNOPSIS
Shows daily backup receipt creation.

.DESCRIPTION
The script writes and validates a local training backup receipt.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$BackupName = 'TrainingDailyBackup'
)

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-user-backup'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $PreviousReceiptPath = Join-Path -Path $DataFolder -ChildPath 'daily-backup-receipt.json'
    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'PreviousDailyReceipt'
        Path = $PreviousReceiptPath
        Exists = Test-Path -Path $PreviousReceiptPath -PathType Leaf
    }

    $Receipt = [pscustomobject]@{
        Stage = 'DailyBackup'
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

    [pscustomobject]@{
        Stage = 'Validate'
        BackupName = $Receipt.BackupName
        ReceiptPath = $ReceiptPath
        Exists = Test-Path -Path $ReceiptPath -PathType Leaf
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
