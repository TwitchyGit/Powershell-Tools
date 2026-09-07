#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

<#
.SYNOPSIS
Runs the CyberArk 14.2 administrator REST API regression suite.

.DESCRIPTION
The runner asks for the administrator user name once and keeps credentials in
memory. All editable environment values live in ConfigModule.psm1 so the same
unchanged test code can be run before and after an upgrade.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve the module beside the runner so execution does not depend on the current directory.
$configModulePath = Join-Path $PSScriptRoot 'ConfigModule.psm1'
Import-Module -Name $configModulePath -Force -Scope Local -ErrorAction Stop
$Defaults = $CybRegressionConfig

if ($Defaults.PVWAUrl -match 'example\.com') {
    throw 'Edit the PVWAUrl value in ConfigModule.psm1 before running the suite.'
}

if ($Defaults.AuthenticationType -notin $Defaults.SupportedAuthTypes) {
    throw "AuthenticationType must be one of: $($Defaults.SupportedAuthTypes -join ', ')."
}

# Ask once because repeated credential prompts make unattended upgrade comparisons unreliable.
$adminUserName = Read-Host 'CyberArk administrator user name'
if ([string]::IsNullOrWhiteSpace($adminUserName)) {
    throw 'An administrator user name is required.'
}

$adminPassword = Read-Host 'CyberArk administrator password' -AsSecureString
$adminCredential = New-Object System.Management.Automation.PSCredential($adminUserName, $adminPassword)

# Keep result files separate from code so timestamped baselines can be retained safely.
if (-not (Test-Path -LiteralPath $Defaults.ResultsDirectory -PathType Container)) {
    $null = New-Item -Path $Defaults.ResultsDirectory -ItemType Directory -Force
}

$testPath = Join-Path $PSScriptRoot 'CyberArk-14.2.Admin.Tests.ps1'
$container = New-PesterContainer -Path $testPath -Data @{
    TestConfig      = $Defaults
    AdminCredential = $adminCredential
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultPath = Join-Path $Defaults.ResultsDirectory "CyberArk-14.2-Admin-REST-$timestamp.xml"

$pesterConfiguration = New-PesterConfiguration
$pesterConfiguration.Run.Container = $container
$pesterConfiguration.Run.PassThru = $true
$pesterConfiguration.Output.Verbosity = $Defaults.OutputVerbosity
$pesterConfiguration.TestResult.Enabled = $true
$pesterConfiguration.TestResult.OutputFormat = 'NUnitXml'
$pesterConfiguration.TestResult.OutputPath = $resultPath

try {
    # Print the suite identity before Pester so combined logs remain self-describing.
    Write-Host "Suite: $($Defaults.AdminSuiteName)"
    $result = Invoke-Pester -Configuration $pesterConfiguration
}
finally {
    # Release credential references promptly and never serialise them into the result file.
    $adminCredential = $null
    $adminPassword = $null
}

Write-Host "Pester result: $resultPath"

if ($result.FailedCount -gt 0) {
    exit 1
}

exit 0
