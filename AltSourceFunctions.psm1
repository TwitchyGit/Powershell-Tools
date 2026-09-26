using module ./PSFunctions.psm1

function New-AltSourcePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceName,

        [Parameter(Mandatory)]
        [string]$PackageName,

        [string]$Content = 'training content from alternate source'
    )

    $AltSourceRoot = Join-SamplePath -ChildPath '.sample-alt-sources'
    $SourceFolder = Join-Path -Path $AltSourceRoot -ChildPath $SourceName
    New-SampleFolder -Path $SourceFolder | Out-Null

    $PackagePath = Join-Path -Path $SourceFolder -ChildPath ('{0}.txt' -f $PackageName)
    Set-Content -Path $PackagePath -Value $Content -ErrorAction Stop
    Write-SampleLog -Message ('Created alternate source package {0}' -f $PackageName) | Out-Null

    [pscustomobject]@{
        SourceName = $SourceName
        PackageName = $PackageName
        PackagePath = $PackagePath
    }
}

function Get-AltSourcePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceName,

        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $AltSourceRoot = Join-SamplePath -ChildPath '.sample-alt-sources'
    $PackagePath = Join-Path -Path $AltSourceRoot -ChildPath $SourceName
    $PackagePath = Join-Path -Path $PackagePath -ChildPath ('{0}.txt' -f $PackageName)

    if (-not (Test-Path -Path $PackagePath -PathType Leaf)) {
        Write-Error -Message ('Alternate source package was not found: {0}' -f $PackagePath) -ErrorAction Stop
    }

    [pscustomobject]@{
        SourceName = $SourceName
        PackageName = $PackageName
        PackagePath = $PackagePath
        Content = Get-Content -Path $PackagePath -Raw -ErrorAction Stop
    }
}

function Copy-AltSourcePackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceName,

        [Parameter(Mandatory)]
        [string]$PackageName
    )

    $Package = Get-AltSourcePackage -SourceName $SourceName -PackageName $PackageName
    $Environment = Get-SampleEnvironment
    $PackageFolder = Join-SamplePath -ChildPath $Environment.Paths.PackageFolder
    New-SampleFolder -Path $PackageFolder | Out-Null

    $DestinationPath = Join-Path -Path $PackageFolder -ChildPath ('{0}.txt' -f $PackageName)
    Copy-Item -Path $Package.PackagePath -Destination $DestinationPath -Force -ErrorAction Stop
    Write-SampleLog -Message ('Copied alternate source package {0}' -f $PackageName) | Out-Null

    [pscustomobject]@{
        SourceName = $SourceName
        PackageName = $PackageName
        SourcePath = $Package.PackagePath
        DestinationPath = $DestinationPath
    }
}

Export-ModuleMember -Function New-AltSourcePackage
Export-ModuleMember -Function Get-AltSourcePackage
Export-ModuleMember -Function Copy-AltSourcePackage
