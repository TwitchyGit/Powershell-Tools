#requires -Version 5.1

<#
.SYNOPSIS
Downloads the latest VS Code extensions and PowerShell modules into a transfer directory.

.DESCRIPTION
Run this script only on the internet-connected computer. It downloads packages but does
not install them. Copy the completed destination directory and Install-VSCodePackages.ps1
to the offline computer when the download has finished.

The output layout is:

    <DestinationPath>\Extensions\*.vsix
    <DestinationPath>\Modules\<ModuleName>\<Version>\*

The script is safe to rerun. VSIX files are updated when their content changes and the
latest stable version of each configured PowerShell module is downloaded.

.PARAMETER DestinationPath
Directory in which the transferable Extensions and Modules folders will be created.
The default is a VSCode-Packages directory beside this script.

.EXAMPLE
    powershell.exe -NoProfile -File .\Save-VSCodePackages.ps1 -DestinationPath 'C:\Transfer\vscode-extensions'

Downloads all configured packages to C:\Transfer\vscode-extensions. Nothing is installed.

.NOTES
To add another VS Code extension, add its publisher.extension ID to $extensionIds.
To add another PowerShell Gallery module, add its name to $moduleNames.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $DestinationPath = (Join-Path -Path $PSScriptRoot -ChildPath 'VSCode-Packages')
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# These are VS Code extension IDs in publisher.extension format.
$extensionIds = @(
    'gitlab.gitlab-workflow'
    'eamodio.gitlens'
    'ms-vscode.notepadplusplus-keybindings'
    'ms-vscode.PowerShell'
    'ironmansoftware.powershellprotools'
)

# Add other PowerShell Gallery module names here when required.
$moduleNames = @(
    'PSScriptAnalyzer'
)

function Read-VsixManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $archive = $null
    $reader = $null

    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
        $manifestEntry = $archive.Entries |
            Where-Object { $_.FullName -ieq 'extension/package.json' } |
            Select-Object -First 1

        if ($null -eq $manifestEntry) {
            Write-Error -Message "The downloaded file is not a valid VS Code VSIX: $Path"
        }

        $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList $manifestEntry.Open()
        $manifest = $reader.ReadToEnd() | ConvertFrom-Json

        [pscustomobject]@{
            ExtensionId = '{0}.{1}' -f $manifest.publisher, $manifest.name
            Version     = [string] $manifest.version
        }
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }

        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

function Save-VSCodeExtension {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[^.]+\.[^.]+$')]
        [string] $ExtensionId,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    $idParts = $ExtensionId -split '\.', 2
    $publisher = [uri]::EscapeDataString($idParts[0])
    $extensionName = [uri]::EscapeDataString($idParts[1])
    $downloadUri = 'https://marketplace.visualstudio.com/_apis/public/gallery/publishers/{0}/vsextensions/{1}/latest/vspackage' -f $publisher, $extensionName
    $targetPath = Join-Path -Path $Path -ChildPath ($ExtensionId + '.vsix')
    $temporaryPath = '{0}.{1}.download' -f $targetPath, ([guid]::NewGuid().ToString('N'))

    Write-Information -InformationAction Continue -MessageData "Checking $ExtensionId ..."

    try {
        Invoke-WebRequest -Uri $downloadUri -OutFile $temporaryPath -UseBasicParsing

        if ((Get-Item -LiteralPath $temporaryPath).Length -eq 0) {
            Write-Error -Message "The Marketplace returned an empty file for $ExtensionId."
        }

        $metadata = Read-VsixManifest -Path $temporaryPath
        if ($metadata.ExtensionId -ine $ExtensionId) {
            Write-Error -Message "Expected $ExtensionId but the downloaded VSIX contains $($metadata.ExtensionId)."
        }

        $downloadHash = (Get-FileHash -LiteralPath $temporaryPath -Algorithm SHA256).Hash
        $status = 'Downloaded'

        if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
            $currentHash = (Get-FileHash -LiteralPath $targetPath -Algorithm SHA256).Hash
            if ($currentHash -eq $downloadHash) {
                $status = 'Already current'
                Remove-Item -LiteralPath $temporaryPath -Force
            }
            else {
                Move-Item -LiteralPath $temporaryPath -Destination $targetPath -Force
                $status = 'Updated'
            }
        }
        else {
            Move-Item -LiteralPath $temporaryPath -Destination $targetPath
        }

        [pscustomobject]@{
            Type    = 'VS Code extension'
            Name    = $ExtensionId
            Version = $metadata.Version
            Status  = $status
            Path    = $targetPath
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Save-LatestPowerShellModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    $saveModuleCommand = Get-Command -Name Save-Module -ErrorAction Stop
    $latestModule = Find-Module -Name $Name -Repository PSGallery -ErrorAction Stop
    $version = [string] $latestModule.Version
    $versionPath = Join-Path -Path $Path -ChildPath (Join-Path -Path $Name -ChildPath $version)
    $alreadyPresent = Test-Path -LiteralPath $versionPath -PathType Container

    Write-Information -InformationAction Continue -MessageData "Checking $Name $version ..."

    if (-not $alreadyPresent) {
        $saveParameters = @{
            Name            = $Name
            RequiredVersion = $version
            Repository      = 'PSGallery'
            Path            = $Path
            Force           = $true
            ErrorAction     = 'Stop'
        }

        # AcceptLicense was added after the PowerShellGet version shipped with some Windows 5.1 systems.
        if ($saveModuleCommand.Parameters.ContainsKey('AcceptLicense')) {
            $saveParameters.AcceptLicense = $true
        }

        Save-Module @saveParameters
    }

    [pscustomobject]@{
        Type    = 'PowerShell module'
        Name    = $Name
        Version = $version
        Status  = if ($alreadyPresent) { 'Already current' } else { 'Downloaded' }
        Path    = $versionPath
    }
}

$originalSecurityProtocol = [Net.ServicePointManager]::SecurityProtocol

try {
    [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $resolvedDestinationPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DestinationPath)
    $extensionPath = Join-Path -Path $resolvedDestinationPath -ChildPath 'Extensions'
    $modulePath = Join-Path -Path $resolvedDestinationPath -ChildPath 'Modules'

    $null = New-Item -Path $extensionPath -ItemType Directory -Force
    $null = New-Item -Path $modulePath -ItemType Directory -Force

    $results = foreach ($extensionId in $extensionIds) {
        Save-VSCodeExtension -ExtensionId $extensionId -Path $extensionPath
    }

    foreach ($moduleName in $moduleNames) {
        $results += Save-LatestPowerShellModule -Name $moduleName -Path $modulePath
    }

    Write-Information -InformationAction Continue -MessageData ''
    Write-Information -InformationAction Continue -MessageData "Packages are staged in: $resolvedDestinationPath"
    $results | Format-Table -AutoSize
}
catch {
    Write-Error -ErrorRecord $_
    exit 1
}
finally {
    [Net.ServicePointManager]::SecurityProtocol = $originalSecurityProtocol
}

exit 0
