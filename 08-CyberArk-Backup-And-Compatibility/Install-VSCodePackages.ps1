<#
.SYNOPSIS
Shows offline package install planning.

.DESCRIPTION
The script reads a local package manifest and reports install actions.

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

    $PackagePath = Join-Path -Path $DataFolder -ChildPath $PackageFile
    if (-not (Test-Path -Path $PackagePath -PathType Leaf)) {
        $DefaultPackages = @(
            [pscustomobject]@{
                Name = 'sample.theme'
                Version = '1.0.0'
                Source = 'TrainingCache'
                Checksum = 'training-theme-100'
            }
            [pscustomobject]@{
                Name = 'sample.tools'
                Version = '2.0.0'
                Source = 'TrainingCache'
                Checksum = 'training-tools-200'
            }
        )

        ConvertTo-Json -InputObject $DefaultPackages -Depth 4 |
            Set-Content -Path $PackagePath -ErrorAction Stop
    }

    $Packages = Get-Content -Path $PackagePath -Raw -ErrorAction Stop | ConvertFrom-Json
    $Results = foreach ($Package in $Packages) {
        [pscustomobject]@{
            Name = $Package.Name
            Version = $Package.Version
            Action = 'WouldInstall'
            HasChecksum = -not [string]::IsNullOrWhiteSpace($Package.Checksum)
            TrainingOnly = $true
        }
    }

    [pscustomobject]@{
        Stage = 'InstallPackages'
        PackagePath = $PackagePath
        PackageCount = $Results.Count
        MissingChecksumCount = ($Results | Where-Object { -not $_.HasChecksum }).Count
        Results = $Results
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
