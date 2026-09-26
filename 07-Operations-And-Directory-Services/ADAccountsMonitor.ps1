<#
.SYNOPSIS
Shows local AD-shaped computer monitoring.

.DESCRIPTION
The script classifies local sample computer records and reports review counts.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ADAccountsMonitor.psm1') -Force -ErrorAction Stop

    $Computers = Get-TrainingAdComputer
    $Results = foreach ($Computer in $Computers) {
        Test-TrainingAdComputer -Computer $Computer
    }

    [pscustomobject]@{
        Stage = 'MonitorComputers'
        CheckedComputers = $Results.Count
        ReadyComputers = ($Results | Where-Object { $_.Status -eq 'Ready' }).Count
        ReviewComputers = ($Results | Where-Object { $_.Status -ne 'Ready' }).Count
        Results = $Results
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
