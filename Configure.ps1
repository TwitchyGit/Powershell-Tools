[CmdletBinding()]
param(
    [string]$RestoreName = 'TrainingAirgapRestore'
)

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-airgap-restore'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Config = [pscustomobject]@{
        RestoreName = $RestoreName
        BackupSet = 'TrainingBackupSet'
        SourceVault = 'TrainingSourceVault'
        TargetVault = 'TrainingAirgapVault'
        Mode = 'TrainingOnly'
    }

    $ConfigPath = Join-Path -Path $DataFolder -ChildPath 'restore-config.json'
    ConvertTo-Json -InputObject $Config -Depth 4 |
        Set-Content -Path $ConfigPath -ErrorAction Stop

    [pscustomobject]@{
        RestoreName = $RestoreName
        ConfigPath = $ConfigPath
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
