<#
.SYNOPSIS
Shows deployment receipt creation.

.DESCRIPTION
The script reads a local manifest and writes a local training receipt.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$ManifestPath
)

try {
    $SharedModule = Join-Path -Path $PSScriptRoot -ChildPath '../05-Modules-And-Configuration/PSFunctions.psm1'
    Import-Module -Name $SharedModule -Force -ErrorAction Stop
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DeploymentFunctions.psm1') -Force -ErrorAction Stop

    $UsedDefaultManifest = $false
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $Environment = Get-SampleEnvironment
        $PackageFile = '{0}.psd1' -f $Environment.Deployment.PackageName
        $PackageFolder = Join-SamplePath -ChildPath $Environment.Paths.PackageFolder
        $ManifestPath = Join-Path -Path $PackageFolder -ChildPath $PackageFile
        $UsedDefaultManifest = $true
    }

    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'ManifestPath'
        Value = $ManifestPath
        UsedDefault = $UsedDefaultManifest
        Passed = Test-Path -Path $ManifestPath -PathType Leaf
    }

    $Result = Invoke-TrainingDeployment -ManifestPath $ManifestPath
    $Result

    [pscustomobject]@{
        Stage = 'Validate'
        Check = 'ReceiptCreated'
        Value = $Result.ReceiptPath
        Passed = Test-Path -Path $Result.ReceiptPath -PathType Leaf
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
