<#
.SYNOPSIS
Shows offline package manifest creation.

.DESCRIPTION
The script writes package version and checksum data for training.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
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
            Checksum = 'training-theme-100'
        }
        [pscustomobject]@{
            Name = 'sample.tools'
            Version = '2.0.0'
            Source = 'TrainingGallery'
            Checksum = 'training-tools-200'
        }
        [pscustomobject]@{
            Name = 'sample.linting'
            Version = '3.1.0'
            Source = 'TrainingGallery'
            Checksum = 'training-linting-310'
        }
    )

    $PackagePath = Join-Path -Path $DataFolder -ChildPath $PackageFile
    ConvertTo-Json -InputObject $Packages -Depth 4 |
        Set-Content -Path $PackagePath -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'SavePackages'
        PackageCount = $Packages.Count
        PackagePath = $PackagePath
        DuplicateNames = @($Packages | Group-Object -Property Name | Where-Object { $_.Count -gt 1 }).Count
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
