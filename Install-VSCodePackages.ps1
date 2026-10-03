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
            }
            [pscustomobject]@{
                Name = 'sample.tools'
                Version = '2.0.0'
                Source = 'TrainingCache'
            }
        )

        ConvertTo-Json -InputObject $DefaultPackages -Depth 4 |
            Set-Content -Path $PackagePath -ErrorAction Stop
    }

    $Packages = Get-Content -Path $PackagePath -Raw -ErrorAction Stop | ConvertFrom-Json
    foreach ($Package in $Packages) {
        [pscustomobject]@{
            Name = $Package.Name
            Version = $Package.Version
            Action = 'WouldInstall'
            TrainingOnly = $true
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
