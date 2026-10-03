<#
.SYNOPSIS
Shows OU-scoped computer scan shape.

.DESCRIPTION
The script reports local sample computer scan counts.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$OrganizationalUnit = 'OU=Training,DC=example,DC=invalid'
)

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ADAccountsMonitor.psm1') -Force -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'OrganizationalUnit'
        Value = $OrganizationalUnit
        Passed = $OrganizationalUnit -like 'OU=*'
    }

    $Computers = Get-TrainingAdComputer -OrganizationalUnit $OrganizationalUnit
    $Results = $Computers | ForEach-Object {
        Test-TrainingAdComputer -Computer $_
    }

    [pscustomobject]@{
        Stage = 'ScanOu'
        OrganizationalUnit = $OrganizationalUnit
        ComputerCount = $Results.Count
        DisabledCount = ($Results | Where-Object { $_.Status -eq 'DisabledTrainingObject' }).Count
        StaleCount = ($Results | Where-Object { $_.Status -eq 'StaleTrainingObject' }).Count
        Results = $Results
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
