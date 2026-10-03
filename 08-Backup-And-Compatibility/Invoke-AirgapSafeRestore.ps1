<#
.SYNOPSIS
Shows airgap restore orchestration.

.DESCRIPTION
The script runs local restore tests and writes a training receipt.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-airgap-restore'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $TestScript = Join-Path -Path $PSScriptRoot -ChildPath 'Test-Restore.ps1'
    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'RestoreTestScript'
        Path = $TestScript
        Exists = Test-Path -Path $TestScript -PathType Leaf
    }

    & $TestScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error -Message 'Training airgap restore test failed.' -ErrorAction Stop
    }

    $Receipt = [pscustomobject]@{
        Stage = 'AirgapRestore'
        RestoreAction = 'WouldRestoreSafes'
        RestoreMode = 'TrainingOnly'
        TestExitCode = $LASTEXITCODE
        CompletedAt = (Get-Date -Format o)
    }

    $ReceiptPath = Join-Path -Path $DataFolder -ChildPath 'restore-receipt.json'
    ConvertTo-Json -InputObject $Receipt -Depth 4 |
        Set-Content -Path $ReceiptPath -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'Validate'
        ReceiptPath = $ReceiptPath
        Exists = Test-Path -Path $ReceiptPath -PathType Leaf
        RestoreMode = $Receipt.RestoreMode
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
