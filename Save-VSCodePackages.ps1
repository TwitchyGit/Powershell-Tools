[CmdletBinding()]
param(
    [string]$PackageFile = 'vscode-packages.json'
)

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-vscode-packages'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Packages = @(
        [pscustomobject]@{
            Name = 'sample.theme'
            Version = '1.0.0'
            Source = 'TrainingGallery'
        }
        [pscustomobject]@{
            Name = 'sample.tools'
            Version = '2.0.0'
            Source = 'TrainingGallery'
        }
        [pscustomobject]@{
            Name = 'sample.linting'
            Version = '3.1.0'
            Source = 'TrainingGallery'
        }
    )

    $PackagePath = Join-Path -Path $DataFolder -ChildPath $PackageFile
    ConvertTo-Json -InputObject $Packages -Depth 4 |
        Set-Content -Path $PackagePath -ErrorAction Stop

    [pscustomobject]@{
        PackageCount = $Packages.Count
        PackagePath = $PackagePath
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
