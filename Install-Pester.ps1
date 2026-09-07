#Requires -Version 5.1
<#
.SYNOPSIS
    Installs Pester from a local .nupkg file into the current user's personal
    PowerShell module path (CurrentUser scope only — no admin rights needed,
    no system module paths touched, fully offline).

.PARAMETER NupkgPath
    Path to the pester.<version>.nupkg file. If omitted, the script looks for
    a single pester*.nupkg file in its own directory.

.PARAMETER Force
    Overwrite an existing copy of the same version if one is already installed.

.EXAMPLE
    .\Install-PesterFromNupkg.ps1 -NupkgPath C:\Downloads\pester.6.1.0.nupkg

.EXAMPLE
    .\Install-PesterFromNupkg.ps1
    # auto-detects a pester*.nupkg sitting next to the script
#>
[CmdletBinding()]
param(
    [string]$NupkgPath,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Resolve-NupkgPath {
    param([string]$Path)

    if ($Path) {
        if (-not (Test-Path -LiteralPath $Path)) {
            throw "Nupkg not found at '$Path'."
        }
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
    $candidates = @(Get-ChildItem -LiteralPath $scriptDir -Filter 'pester*.nupkg' -File -ErrorAction SilentlyContinue)

    if ($candidates.Count -eq 0) {
        throw "No pester*.nupkg found in '$scriptDir'. Pass -NupkgPath explicitly."
    }
    if ($candidates.Count -gt 1) {
        throw "Multiple pester*.nupkg files found in '$scriptDir'. Pass -NupkgPath explicitly."
    }
    return $candidates[0].FullName
}

function Get-PesterVersionFromFileName {
    param([string]$FileName)

    if ($FileName -match 'pester\.(\d+\.\d+\.\d+(?:[-.][A-Za-z0-9]+)?)\.nupkg$') {
        return $Matches[1]
    }
    return $null
}

# --- Locate source file ---
$nupkg = Resolve-NupkgPath -Path $NupkgPath
Write-Host "Using nupkg: $nupkg" -ForegroundColor Cyan

$version = Get-PesterVersionFromFileName -FileName (Split-Path -Leaf $nupkg)

# --- Extract (a .nupkg is a zip file) ---
$work = Join-Path ([System.IO.Path]::GetTempPath()) ("PesterInstall_" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null

try {
    $zipCopy = Join-Path $work 'package.zip'
    Copy-Item -LiteralPath $nupkg -Destination $zipCopy

    $extractDir = Join-Path $work 'extracted'
    Expand-Archive -LiteralPath $zipCopy -DestinationPath $extractDir -Force

    # Find the folder that actually contains Pester.psd1 (layout varies by packaging)
    $manifest = Get-ChildItem -LiteralPath $extractDir -Filter 'Pester.psd1' -Recurse | Select-Object -First 1
    if (-not $manifest) {
        throw "Could not find Pester.psd1 inside the extracted package. This may not be a valid Pester nupkg."
    }
    $moduleSource = $manifest.Directory.FullName

    if (-not $version) {
        $manifestData = Import-PowerShellDataFile -LiteralPath $manifest.FullName
        $version = $manifestData.ModuleVersion
    }
    if (-not $version) {
        throw "Could not determine Pester version from filename or manifest."
    }
    Write-Host "Detected Pester version: $version" -ForegroundColor Cyan

    # --- CurrentUser module target (matches this PowerShell edition) ---
    $docsFolder = if ($PSVersionTable.PSEdition -eq 'Core') { 'PowerShell' } else { 'WindowsPowerShell' }
    $userModuleRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "$docsFolder\Modules"
    $target = Join-Path $userModuleRoot "Pester\$version"

    if (Test-Path -LiteralPath $target) {
        if (-not $Force) {
            throw "Pester $version is already installed at '$target'. Re-run with -Force to overwrite."
        }
        Remove-Item -LiteralPath $target -Recurse -Force
    }

    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Copy-Item -Path (Join-Path $moduleSource '*') -Destination $target -Recurse -Force

    Write-Host "Installed Pester $version to '$target'" -ForegroundColor Green
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# --- Verify ---
Import-Module Pester -RequiredVersion $version -Force
$installed = Get-Module Pester
Write-Host "Import verified: Pester $($installed.Version) loaded from $($installed.ModuleBase)" -ForegroundColor Green
Write-Host "Note: Windows Server ships an old built-in Pester (often 3.4.0). Always use -RequiredVersion $version (or -MinimumVersion) when importing to make sure this one is used." -ForegroundColor Yellow
