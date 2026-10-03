<#
.SYNOPSIS
Provides local deployment training functions.

.DESCRIPTION
The module creates key material, package manifests and deployment receipts.

.NOTES
This module is training material. It uses local sample data unless a caller supplies another path.
#>
using module ../05-Modules-And-Configuration/PSFunctions.psm1

function New-TrainingGitKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$KeyName
    )

    $Environment = Get-SampleEnvironment
    $KeyFolder = Join-SamplePath -ChildPath $Environment.Paths.KeyFolder
    New-SampleFolder -Path $KeyFolder | Out-Null

    $PrivateKeyPath = Join-Path -Path $KeyFolder -ChildPath $KeyName
    $PublicKeyPath = '{0}.pub' -f $PrivateKeyPath
    $FingerprintPath = '{0}.fingerprint.txt' -f $PrivateKeyPath
    $KeyMaterial = 'sample-private-key-training-only'
    $PublicMaterial = 'sample-public-key-training-only'
    $Fingerprint = 'sample:{0}:{1}' -f $KeyName, (Get-Date -Format 'yyyyMMddHHmmss')

    Set-Content -Path $PrivateKeyPath -Value $KeyMaterial -ErrorAction Stop
    Set-Content -Path $PublicKeyPath -Value $PublicMaterial -ErrorAction Stop
    Set-Content -Path $FingerprintPath -Value $Fingerprint -ErrorAction Stop

    Write-SampleLog -Message ('Created sample key files for {0}' -f $KeyName) | Out-Null

    [pscustomobject]@{
        Stage = 'SetupKey'
        KeyName = $KeyName
        PrivateKeyPath = $PrivateKeyPath
        PublicKeyPath = $PublicKeyPath
        FingerprintPath = $FingerprintPath
        PrivateKeyExists = Test-Path -Path $PrivateKeyPath -PathType Leaf
        PublicKeyExists = Test-Path -Path $PublicKeyPath -PathType Leaf
        Fingerprint = $Fingerprint
        TrainingOnly = $true
    }
}

function New-DeploymentManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [Parameter(Mandatory)]
        [string]$Version
    )

    $Environment = Get-SampleEnvironment
    $PackageFolder = Join-SamplePath -ChildPath $Environment.Paths.PackageFolder
    New-SampleFolder -Path $PackageFolder | Out-Null

    $SourceFiles = @(
        'Deploy-GitRepository.ps1'
        'Prepare-Deployment.ps1'
        'Invoke-Deployment.ps1'
        'Setup-GitRepoKeys.ps1'
    )
    $SourceDigest = ($SourceFiles | Sort-Object) -join '|'
    $SourceFileList = ($SourceFiles | ForEach-Object { "        '$_'" }) -join [Environment]::NewLine
    $ManifestPath = Join-Path -Path $PackageFolder -ChildPath ('{0}.psd1' -f $PackageName)
    $Manifest = @"
@{
    PackageName = '$PackageName'
    Version = '$Version'
    CreatedAt = '$(Get-Date -Format o)'
    SourceRoot = 'Code Samples'
    SourceFiles = @(
$SourceFileList
    )
    SourceDigest = '$SourceDigest'
    EnvironmentName = '$($Environment.Deployment.EnvironmentName)'
}
"@

    Set-Content -Path $ManifestPath -Value $Manifest -ErrorAction Stop
    Write-SampleLog -Message ('Prepared package manifest {0}' -f $PackageName) | Out-Null

    [pscustomobject]@{
        Stage = 'PrepareManifest'
        PackageName = $PackageName
        Version = $Version
        ManifestPath = $ManifestPath
        SourceFileCount = $SourceFiles.Count
        SourceDigest = $SourceDigest
    }
}

function Invoke-TrainingDeployment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    if (-not (Test-Path -Path $ManifestPath -PathType Leaf)) {
        Write-Error -Message ('Manifest was not found: {0}' -f $ManifestPath) -ErrorAction Stop
    }

    $Manifest = Import-PowerShellDataFile -Path $ManifestPath
    $Environment = Get-SampleEnvironment
    $DeploymentFolder = Join-SamplePath -ChildPath $Environment.Paths.DeploymentFolder
    New-SampleFolder -Path $DeploymentFolder | Out-Null

    $ReceiptPath = Join-Path -Path $DeploymentFolder -ChildPath ('{0}.receipt.txt' -f $Manifest.PackageName)
    $ReceiptLines = @(
        'PackageName={0}' -f $Manifest.PackageName
        'Version={0}' -f $Manifest.Version
        'EnvironmentName={0}' -f $Environment.Deployment.EnvironmentName
        'ManifestPath={0}' -f $ManifestPath
        'CompletedAt={0}' -f (Get-Date -Format o)
        'Result=Success'
    )

    Set-Content -Path $ReceiptPath -Value $ReceiptLines -ErrorAction Stop
    Write-SampleLog -Message ('Deployed {0} version {1}' -f $Manifest.PackageName, $Manifest.Version) | Out-Null

    [pscustomobject]@{
        Stage = 'InvokeDeployment'
        PackageName = $Manifest.PackageName
        Version = $Manifest.Version
        EnvironmentName = $Environment.Deployment.EnvironmentName
        ManifestPath = $ManifestPath
        ReceiptPath = $ReceiptPath
        ReceiptLineCount = $ReceiptLines.Count
    }
}

Export-ModuleMember -Function New-TrainingGitKey
Export-ModuleMember -Function New-DeploymentManifest
Export-ModuleMember -Function Invoke-TrainingDeployment
