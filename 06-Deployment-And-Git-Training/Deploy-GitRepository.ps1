<#
.SYNOPSIS
Shows an end-to-end local deployment flow.

.DESCRIPTION
The script runs setup, manifest preparation and deployment receipt stages.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $SetupScript = Join-Path -Path $PSScriptRoot -ChildPath 'Setup-GitRepoKeys.ps1'
    $PrepareScript = Join-Path -Path $PSScriptRoot -ChildPath 'Prepare-Deployment.ps1'
    $InvokeScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-Deployment.ps1'

    $Stages = @(
        [pscustomobject]@{ Name = 'SetupKey'; Script = $SetupScript },
        [pscustomobject]@{ Name = 'PrepareManifest'; Script = $PrepareScript },
        [pscustomobject]@{ Name = 'InvokeDeployment'; Script = $InvokeScript }
    )
    $StageResults = @()

    foreach ($Stage in $Stages) {
        [pscustomobject]@{
            Stage = $Stage.Name
            Check = 'ScriptExists'
            Value = $Stage.Script
            Passed = Test-Path -Path $Stage.Script -PathType Leaf
        }
    }

    & $SetupScript
    $StageResults += [pscustomobject]@{ Stage = 'SetupKey'; ExitCode = $LASTEXITCODE }
    if ($StageResults[-1].ExitCode -ne 0) {
        Write-Error -Message 'Sample key setup failed.' -ErrorAction Stop
    }

    & $PrepareScript
    $StageResults += [pscustomobject]@{ Stage = 'PrepareManifest'; ExitCode = $LASTEXITCODE }
    if ($StageResults[-1].ExitCode -ne 0) {
        Write-Error -Message 'Sample deployment preparation failed.' -ErrorAction Stop
    }

    & $InvokeScript
    $StageResults += [pscustomobject]@{ Stage = 'InvokeDeployment'; ExitCode = $LASTEXITCODE }
    if ($StageResults[-1].ExitCode -ne 0) {
        Write-Error -Message 'Sample deployment invocation failed.' -ErrorAction Stop
    }

    [pscustomobject]@{
        Stage = 'DeploymentSummary'
        CompletedStages = $StageResults.Count
        FailedStages = ($StageResults | Where-Object { $_.ExitCode -ne 0 }).Count
        Result = 'Success'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
