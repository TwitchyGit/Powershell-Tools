<#
.SYNOPSIS
Checks the deployment-tool training sample set.

.DESCRIPTION
The script parses local scripts, validates fixture configuration and runs report-only decision logic.

.NOTES
The script performs local validation only. It does not test live remoting, Git remote or credential behavior.
#>
[CmdletBinding()]
param()

try {
    $ScriptFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' -File |
        Where-Object { $_.Name -ne 'Test-DeploymentTool.ps1' } |
        Sort-Object -Property Name
    $ModuleFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.psm1' -File |
        Sort-Object -Property Name
    $PowerShellFiles = @($ScriptFiles) + @($ModuleFiles)

    $ParseErrors = foreach ($PowerShellFile in $PowerShellFiles) {
        $Tokens = $null
        $Errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile(
            $PowerShellFile.FullName,
            [ref]$Tokens,
            [ref]$Errors
        ) |
            Out-Null

        foreach ($ErrorItem in $Errors) {
            [pscustomobject]@{
                File = $PowerShellFile.Name
                Message = $ErrorItem.Message
            }
        }
    }

    if ($ParseErrors) {
        $ParseErrors
        Write-Error -Message 'One or more deployment-tool files failed parser checks.' -ErrorAction Stop
    }

    $ModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'DeploymentTool.psm1'
    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/deployment-tool-config.json'
    $ExpectedPath = Join-Path -Path $PSScriptRoot -ChildPath 'expected/deployment-tool-summary.json'
    Import-Module -Name $ModulePath -Force -ErrorAction Stop

    $Config = Import-DeploymentToolConfig -Path $ConfigPath
    $Findings = Test-DeploymentToolConfig -Config $Config
    $FailedFindings = @($Findings | Where-Object { $_.Result -eq 'Fail' })
    $Report = Invoke-DeploymentToolPlan -Config $Config -ReportOnly -Unattended
    $Expected = Get-Content -Path $ExpectedPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

    $Summary = [pscustomobject]@{
        Scripts = $ScriptFiles.Count
        Modules = $ModuleFiles.Count
        ParserErrors = @($ParseErrors).Count
        ValidationFailures = $FailedFindings.Count
        Decisions = @($Report.Decisions).Count
        StageResults = @($Report.StageResults).Count
        ExpectedDecisions = $Expected.ExpectedDecisions
        ExpectedStageResults = $Expected.ExpectedStageResults
    }

    $Summary

    if ($Summary.Decisions -ne $Expected.ExpectedDecisions) {
        Write-Error -Message 'Decision count did not match expected output.' -ErrorAction Stop
    }

    if ($Summary.StageResults -ne $Expected.ExpectedStageResults) {
        Write-Error -Message 'Stage-result count did not match expected output.' -ErrorAction Stop
    }

    if ($Summary.ValidationFailures -ne 0) {
        Write-Error -Message 'Configuration validation returned failures.' -ErrorAction Stop
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
