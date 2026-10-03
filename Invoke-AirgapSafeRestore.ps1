[CmdletBinding()]
param()

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-airgap-restore'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $TestScript = Join-Path -Path $PSScriptRoot -ChildPath 'Test-Restore.ps1'
    & $TestScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error -Message 'Training airgap restore test failed.' -ErrorAction Stop
    }

    $Receipt = [pscustomobject]@{
        RestoreAction = 'WouldRestoreSafes'
        RestoreMode = 'TrainingOnly'
        CompletedAt = (Get-Date -Format o)
    }

    $ReceiptPath = Join-Path -Path $DataFolder -ChildPath 'restore-receipt.json'
    ConvertTo-Json -InputObject $Receipt -Depth 4 |
        Set-Content -Path $ReceiptPath -ErrorAction Stop

    $Receipt

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
