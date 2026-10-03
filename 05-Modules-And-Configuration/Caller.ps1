<#
.SYNOPSIS
Shows multi-script orchestration.

.DESCRIPTION
The script runs local training scripts and reports exit codes.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $CourseRoot = Split-Path -Path $PSScriptRoot -Parent
    $Scripts = @(
        '05-Modules-And-Configuration/Set-Conf.ps1'
        '05-Modules-And-Configuration/Set-Conf-User.ps1'
        '07-Operations-And-Directory-Services/AddGroup-Member.ps1'
        '07-Operations-And-Directory-Services/Scan-ADComputerOU.ps1'
        '08-Backup-And-Compatibility/PAS-CreateObjectList.ps1'
        '08-Backup-And-Compatibility/PAS-ProcessFailedObjects.ps1'
        '08-Backup-And-Compatibility/AutosysRunfile.ps1'
    )

    foreach ($Script in $Scripts) {
        $ScriptPath = Join-Path -Path $CourseRoot -ChildPath $Script
        [pscustomobject]@{
            Stage = 'Preflight'
            Script = $Script
            Exists = Test-Path -Path $ScriptPath -PathType Leaf
        }

        & $ScriptPath
        $ExitCode = $LASTEXITCODE
        [pscustomobject]@{
            Stage = 'Complete'
            Script = $Script
            ExitCode = $ExitCode
        }

        if ($ExitCode -ne 0) {
            Write-Error -Message ('Training script failed: {0}' -f $Script) -ErrorAction Stop
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}

