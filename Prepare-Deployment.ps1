[CmdletBinding()]
param()

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PSFunctions.psm1') -Force -ErrorAction Stop
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DeploymentFunctions.psm1') -Force -ErrorAction Stop

    $Environment = Get-SampleEnvironment
    $Result = New-DeploymentManifest -PackageName $Environment.Deployment.PackageName -Version $Environment.Deployment.Version
    $Result

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
