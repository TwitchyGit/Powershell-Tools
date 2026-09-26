<#
.SYNOPSIS
Shows restore test stages.

.DESCRIPTION
The script runs configure, inventory and verification stages locally.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $ConfigureScript = Join-Path -Path $PSScriptRoot -ChildPath '../05-Modules-And-Configuration/Configure.ps1'
    $InventoryScript = Join-Path -Path $PSScriptRoot -ChildPath 'Get-SafeInventory.ps1'
    $VerifyScript = Join-Path -Path $PSScriptRoot -ChildPath 'Verify-RestoredSafes.ps1'
    $Steps = @(
        [pscustomobject]@{ Name = 'Configure'; Script = $ConfigureScript },
        [pscustomobject]@{ Name = 'Inventory'; Script = $InventoryScript },
        [pscustomobject]@{ Name = 'Verify'; Script = $VerifyScript }
    )
    $StepResults = @()

    foreach ($Step in $Steps) {
        [pscustomobject]@{
            Stage = 'Preflight'
            Step = $Step.Name
            Script = $Step.Script
            Exists = Test-Path -Path $Step.Script -PathType Leaf
        }

        & $Step.Script
        $StepResults += [pscustomobject]@{
            Step = $Step.Name
            ExitCode = $LASTEXITCODE
        }

        if ($LASTEXITCODE -ne 0) {
            Write-Error -Message ('Training restore step failed: {0}' -f $Step.Name) -ErrorAction Stop
        }
    }

    [pscustomobject]@{
        Stage = 'RestoreTestSummary'
        CompletedSteps = $StepResults.Count
        FailedSteps = ($StepResults | Where-Object { $_.ExitCode -ne 0 }).Count
        Result = 'Success'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
