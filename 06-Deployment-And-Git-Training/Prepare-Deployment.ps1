<#
.SYNOPSIS
Shows deployment manifest preparation.

.DESCRIPTION
The script builds a local PSD1 manifest from training configuration.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $SharedModule = Join-Path -Path $PSScriptRoot -ChildPath '../05-Modules-And-Configuration/PSFunctions.psm1'
    Import-Module -Name $SharedModule -Force -ErrorAction Stop
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DeploymentFunctions.psm1') -Force -ErrorAction Stop

    $Environment = Get-SampleEnvironment
    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'EnvironmentLoaded'
        Value = $Environment.Deployment.EnvironmentName
        Passed = $true
    }

    $ManifestParams = @{
        PackageName = $Environment.Deployment.PackageName
        Version = $Environment.Deployment.Version
    }
    $Result = New-DeploymentManifest @ManifestParams
    $Result

    [pscustomobject]@{
        Stage = 'Validate'
        Check = 'ManifestCreated'
        Value = $Result.ManifestPath
        Passed = Test-Path -Path $Result.ManifestPath -PathType Leaf
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
