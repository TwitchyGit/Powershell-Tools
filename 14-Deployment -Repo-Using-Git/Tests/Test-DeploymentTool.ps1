using module ../Classes/DeploymentTool.Classes.psm1
<#
.SYNOPSIS
    Runs static checks that prove the tool files parse and the catalogue rejects unsafe values.
#>
[CmdletBinding()]
param()

$Root = Split-Path -Path $PSScriptRoot -Parent
$Files = @(
    'Classes/DeploymentTool.Classes.psm1',
    'Classes/DeploymentModels.ps1',
    'DeploymentSettings.ps1',
    'Classes/RepoRefreshEngine.ps1',
    'Classes/DeploymentConfigurator.ps1',
    'Invoke-RepoRefresh.ps1',
    'Run-Pull-Repo.ps1',
    'Configure-Deployment.ps1'
)

$Failed = $false
foreach ($File in $Files) {
    $Path = Join-Path -Path $Root -ChildPath $File
    $Tokens = $null
    $Errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $Tokens, [ref] $Errors) | Out-Null
    if ($Errors.Count -gt 0) {
        $Failed = $true
        Write-Error -Message "Parser errors in ${Path}: $($Errors.Message -join '; ')"
    }
}

. (Join-Path -Path $Root -ChildPath 'DeploymentSettings.ps1')

$Catalogue = Get-CheckedCatalogue
if ($Catalogue.Count -lt 1) {
    $Failed = $true
    Write-Error -Message 'Catalogue returned no packages.'
}

if (-not (Test-DeploymentPath -Path 'C:\Repo1')) {
    $Failed = $true
    Write-Error -Message 'Expected valid drive C path was rejected.'
}

if (Test-DeploymentPath -Path 'Z:\Repo1') {
    $Failed = $true
    Write-Error -Message 'Expected invalid drive Z path was accepted.'
}

if (-not (Test-SourcePath -SourcePath 'group/repo1.git')) {
    $Failed = $true
    Write-Error -Message 'Expected source path was rejected.'
}

if (Test-SourcePath -SourcePath '../repo1.git') {
    $Failed = $true
    Write-Error -Message 'Expected unsafe source path was accepted.'
}

if ($Failed) {
    exit 1
}

Write-Output 'Static deployment tool checks passed.'
exit 0
