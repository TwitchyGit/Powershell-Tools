<#
.SYNOPSIS
Runs the deployment-tool training orchestrator against a local fixture.

.DESCRIPTION
The script validates configuration, resolves branch decisions and simulates shared stage execution.

.NOTES
The script performs local training validation only. It does not contact live hosts or remote source systems.
#>
[CmdletBinding()]
param(
    [string]
    $ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/deployment-tool-config.json'),

    [string]
    $ReportPath = (Join-Path -Path $PSScriptRoot -ChildPath '.sample-state/deployment-report.json'),

    [switch]
    $ReportOnly,

    [switch]
    $Unattended
)

try {
    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'DeploymentTool.psm1'
    Import-Module -Name $ModulePath -Force -ErrorAction Stop

    $Config = Import-DeploymentToolConfig -Path $ConfigPath
    $Report = Invoke-DeploymentToolPlan -Config $Config -ReportOnly:$ReportOnly -Unattended:$Unattended
    Export-DeploymentToolReport -Report $Report -Path $ReportPath

    $Report.Messages | Format-Table -AutoSize

    if (-not $Report.Passed) {
        Write-Error -Message 'Deployment-tool training run failed validation.' -ErrorAction Stop
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
