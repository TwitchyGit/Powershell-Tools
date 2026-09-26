<#
.SYNOPSIS
Shows weekly backup receipt creation.

.DESCRIPTION
The script writes a local receipt with retention and recovery point data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$BackupName = 'TrainingWeeklyBackup'
)

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-user-backup'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $RetentionDays = 35
    $Receipt = [pscustomobject]@{
        Stage = 'WeeklyBackup'
        BackupName = $BackupName
        Schedule = 'Weekly'
        IncludesSafes = $true
        IncludesReports = $true
        RetentionDays = $RetentionDays
        RecoveryPoint = Get-Date -Format 'yyyy-MM-dd'
        CompletedAt = (Get-Date -Format o)
        TrainingOnly = $true
    }

    $ReceiptPath = Join-Path -Path $DataFolder -ChildPath 'weekly-backup-receipt.json'
    ConvertTo-Json -InputObject $Receipt -Depth 4 |
        Set-Content -Path $ReceiptPath -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'Validate'
        BackupName = $Receipt.BackupName
        ReceiptPath = $ReceiptPath
        RetentionDays = $RetentionDays
        Exists = Test-Path -Path $ReceiptPath -PathType Leaf
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
