using module ./PSFunctions.psm1

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

    Set-Content -Path $PrivateKeyPath -Value 'sample-private-key-training-only' -ErrorAction Stop
    Set-Content -Path $PublicKeyPath -Value 'sample-public-key-training-only' -ErrorAction Stop
    Set-Content -Path $FingerprintPath -Value ('sample:{0}' -f $KeyName) -ErrorAction Stop

    Write-SampleLog -Message ('Created sample key files for {0}' -f $KeyName) | Out-Null

    [pscustomobject]@{
        PrivateKeyPath = $PrivateKeyPath
        PublicKeyPath = $PublicKeyPath
        FingerprintPath = $FingerprintPath
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

    $ManifestPath = Join-Path -Path $PackageFolder -ChildPath ('{0}.psd1' -f $PackageName)
    $Manifest = @"
@{
    PackageName = '$PackageName'
    Version = '$Version'
    CreatedAt = '$(Get-Date -Format o)'
    SourceRoot = 'Code Samples'
}
"@

    Set-Content -Path $ManifestPath -Value $Manifest -ErrorAction Stop
    Write-SampleLog -Message ('Prepared package manifest {0}' -f $PackageName) | Out-Null

    [pscustomobject]@{
        PackageName = $PackageName
        Version = $Version
        ManifestPath = $ManifestPath
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
    $Receipt = 'Deployed {0} version {1} to {2}' -f $Manifest.PackageName, $Manifest.Version,
        $Environment.Deployment.EnvironmentName

    Set-Content -Path $ReceiptPath -Value $Receipt -ErrorAction Stop
    Write-SampleLog -Message $Receipt | Out-Null

    [pscustomobject]@{
        PackageName = $Manifest.PackageName
        Version = $Manifest.Version
        ReceiptPath = $ReceiptPath
    }
}

Export-ModuleMember -Function New-TrainingGitKey
Export-ModuleMember -Function New-DeploymentManifest
Export-ModuleMember -Function Invoke-TrainingDeployment
