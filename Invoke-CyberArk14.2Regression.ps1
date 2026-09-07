#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

<#
.SYNOPSIS
Runs the CyberArk 14.2 user and Safe REST API regression suite.

.DESCRIPTION
Edit ConfigModule.psm1 before the first run. The script asks for the
administrator user name once and asks separately for its password. Credentials
are held in memory only and are not written to the test result file.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Resolve from the script directory so the suite works regardless of the caller's location.
$configModulePath = Join-Path $PSScriptRoot 'ConfigModule.psm1'
Import-Module -Name $configModulePath -Force -Scope Local -ErrorAction Stop
$Defaults = $CybRegressionConfig

if ($Defaults.PVWAUrl -match 'example\.com') {
    throw 'Edit the PVWAUrl value in ConfigModule.psm1 before running the suite.'
}

if ($Defaults.AuthenticationType -notin $Defaults.SupportedAuthTypes) {
    throw "AuthenticationType must be one of: $($Defaults.SupportedAuthTypes -join ', ')."
}

if ([string]::IsNullOrWhiteSpace($Defaults.TestObjectPrefix) -or $Defaults.TestObjectPrefix.Length -gt $Defaults.MaximumPrefixLength) {
    throw "TestObjectPrefix must contain 1 to $($Defaults.MaximumPrefixLength) characters so generated Safe names remain within the 28-character limit."
}

# Ask for the administrator identity once; the generated end user needs no operator input.
$adminUserName = Read-Host 'CyberArk administrator user name'
if ([string]::IsNullOrWhiteSpace($adminUserName)) {
    throw 'An administrator user name is required.'
}

$adminPassword = Read-Host 'CyberArk administrator password' -AsSecureString
$adminCredential = New-Object System.Management.Automation.PSCredential($adminUserName, $adminPassword)

# Create only the suite's own output folder and never write credentials into it.
if (-not (Test-Path -LiteralPath $Defaults.ResultsDirectory -PathType Container)) {
    $null = New-Item -Path $Defaults.ResultsDirectory -ItemType Directory -Force
}

$testPath = Join-Path $PSScriptRoot 'CyberArk-14.2.UserSafe.Tests.ps1'
$container = New-PesterContainer -Path $testPath -Data @{
    TestConfig     = $Defaults
    AdminCredential = $adminCredential
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultPath = Join-Path $Defaults.ResultsDirectory "CyberArk-14.2-UserSafe-REST-$timestamp.xml"

$pesterConfiguration = New-PesterConfiguration
$pesterConfiguration.Run.Container = $container
$pesterConfiguration.Run.PassThru = $true
$pesterConfiguration.Output.Verbosity = $Defaults.OutputVerbosity
$pesterConfiguration.TestResult.Enabled = $true
$pesterConfiguration.TestResult.OutputFormat = 'NUnitXml'
$pesterConfiguration.TestResult.OutputPath = $resultPath

try {
    # Print the suite identity before Pester so mixed upgrade logs remain easy to interpret.
    Write-Host "Suite: $($Defaults.UserSafeSuiteName)"
    $result = Invoke-Pester -Configuration $pesterConfiguration
}
finally {
    # Drop the runner's credential references as soon as Pester has completed.
    $adminCredential = $null
    $adminPassword = $null
}

Write-Host "Pester result: $resultPath"

if ($result.FailedCount -gt 0) {
    exit 1
}

exit 0
