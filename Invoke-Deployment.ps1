[CmdletBinding()]
param(
    [string]$ManifestPath
)

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PSFunctions.psm1') -Force -ErrorAction Stop
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DeploymentFunctions.psm1') -Force -ErrorAction Stop

    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $Environment = Get-SampleEnvironment
        $PackageFile = '{0}.psd1' -f $Environment.Deployment.PackageName
        $PackageFolder = Join-SamplePath -ChildPath $Environment.Paths.PackageFolder
        $ManifestPath = Join-Path -Path $PackageFolder -ChildPath $PackageFile
    }

    $Result = Invoke-TrainingDeployment -ManifestPath $ManifestPath
    $Result

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
