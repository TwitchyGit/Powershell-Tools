<#
.SYNOPSIS
Shows restore configuration generation.

.DESCRIPTION
The script writes local training restore configuration and validates the file.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$RestoreName = 'TrainingAirgapRestore'
)

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-airgap-restore'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'RestoreName'
        Value = $RestoreName
        Passed = -not [string]::IsNullOrWhiteSpace($RestoreName)
    }

    $Config = [pscustomobject]@{
        RestoreName = $RestoreName
        BackupSet = 'TrainingBackupSet'
        SourceVault = 'TrainingSourceVault'
        TargetVault = 'TrainingAirgapVault'
        Mode = 'TrainingOnly'
        CreatedAt = (Get-Date -Format o)
    }

    $ConfigPath = Join-Path -Path $DataFolder -ChildPath 'restore-config.json'
    ConvertTo-Json -InputObject $Config -Depth 4 |
        Set-Content -Path $ConfigPath -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'ConfigureRestore'
        RestoreName = $RestoreName
        ConfigPath = $ConfigPath
        Exists = Test-Path -Path $ConfigPath -PathType Leaf
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
