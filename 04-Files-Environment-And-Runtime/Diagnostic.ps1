<#
.SYNOPSIS
Shows local runtime diagnostics.

.DESCRIPTION
The script reports host facts and local training scope.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $TempPath = [System.IO.Path]::GetTempPath()
    $Checks = @(
        [pscustomobject]@{
            Name = 'SampleFolder'
            Result = 'Pass'
            Detail = $PSScriptRoot
        }
        [pscustomobject]@{
            Name = 'PowerShellVersion'
            Result = 'Info'
            Detail = $PSVersionTable.PSVersion.ToString()
        }
        [pscustomobject]@{
            Name = 'PSEdition'
            Result = 'Info'
            Detail = $PSVersionTable.PSEdition
        }
        [pscustomobject]@{
            Name = 'TempPath'
            Result = if ([string]::IsNullOrWhiteSpace($TempPath)) { 'Fail' } else { 'Pass' }
            Detail = $TempPath
        }
        [pscustomobject]@{
            Name = 'TrainingScope'
            Result = 'Pass'
            Detail = 'No live service checks are performed.'
        }
    )

    [pscustomobject]@{
        Stage = 'RuntimeDiagnostics'
        CheckCount = $Checks.Count
        FailedCount = ($Checks | Where-Object { $_.Result -eq 'Fail' }).Count
        Checks = $Checks
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
