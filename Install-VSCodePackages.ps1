#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()][string]$PackagePath,

    [Parameter()][string]$CodePath,

    [Parameter()][string]$ModuleInstallPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

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
            Write-Error -Message "The file is not a valid VS Code VSIX: $Path"
        }

        $reader = New-Object -TypeName System.IO.StreamReader -ArgumentList $manifestEntry.Open()
        $manifest = $reader.ReadToEnd() | ConvertFrom-Json
        $dependencies = @()

        if ($manifest.PSObject.Properties.Name -contains 'extensionDependencies') {
            $dependencies = @($manifest.extensionDependencies)
        }

        [pscustomobject]@{
            ExtensionId  = '{0}.{1}' -f $manifest.publisher, $manifest.name
            Version      = [string] $manifest.version
            Dependencies = $dependencies
            Path         = $Path
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

function Resolve-CodeCommand {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string] $RequestedPath
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (-not (Test-Path -LiteralPath $RequestedPath -PathType Leaf)) {
            Write-Error -Message "The specified VS Code command was not found: $RequestedPath"
        }

        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($RequestedPath)
    }

    $codeCommand = Get-Command -Name 'code.cmd' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if ($null -eq $codeCommand) {
        $codeCommand = Get-Command -Name 'code' -CommandType Application -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }

    if ($null -ne $codeCommand) {
        return $codeCommand.Source
    }

    $candidatePaths = @()

    if (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        $candidatePaths += Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\Microsoft VS Code\bin\code.cmd'
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) {
        $candidatePaths += Join-Path -Path $env:ProgramFiles -ChildPath 'Microsoft VS Code\bin\code.cmd'
    }

    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
        $candidatePaths += Join-Path -Path $programFilesX86 -ChildPath 'Microsoft VS Code\bin\code.cmd'
    }

    foreach ($candidatePath in $candidatePaths) {
        if (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
            return $candidatePath
        }
    }

    Write-Error -Message 'VS Code was not found. Add code.cmd to PATH or pass its full path with -CodePath.'
}

function Resolve-VsixDependencyOrder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Package
    )

    $remaining = New-Object -TypeName System.Collections.ArrayList
    foreach ($item in $Package) {
        $null = $remaining.Add($item)
    }

    $localIds = @{}
    foreach ($item in $Package) {
        $localIds[$item.ExtensionId.ToLowerInvariant()] = $true
    }

    $ordered = New-Object -TypeName 'System.Collections.Generic.List[object]'

    while ($remaining.Count -gt 0) {
        $madeProgress = $false

        foreach ($item in @($remaining)) {
            $waitingForLocalDependency = $false

            foreach ($dependency in $item.Dependencies) {
                $dependencyId = ([string] $dependency).ToLowerInvariant()
                if (-not $localIds.ContainsKey($dependencyId)) {
                    continue
                }

                foreach ($waitingPackage in $remaining) {
                    if ($waitingPackage.ExtensionId -ieq $dependency) {
                        $waitingForLocalDependency = $true
                        break
                    }
                }

                if ($waitingForLocalDependency) {
                    break
                }
            }

            if (-not $waitingForLocalDependency) {
                $ordered.Add($item)
                $remaining.Remove($item)
                $madeProgress = $true
            }
        }

        if (-not $madeProgress) {
            # A dependency cycle should not stop VS Code from attempting the local packages.
            foreach ($item in @($remaining | Sort-Object -Property ExtensionId)) {
                $ordered.Add($item)
            }
            $remaining.Clear()
        }
    }

    return $ordered.ToArray()
}

function Get-PowerShellModulePackage {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return @()
    }

    $packages = @()

    foreach ($moduleDirectory in Get-ChildItem -LiteralPath $Path -Directory) {
        $manifestName = $moduleDirectory.Name + '.psd1'
        $manifests = Get-ChildItem -LiteralPath $moduleDirectory.FullName -Filter $manifestName -File -Recurse

        foreach ($manifest in $manifests) {
            try {
                $manifestData = Import-PowerShellDataFile -Path $manifest.FullName
                if (-not $manifestData.ContainsKey('ModuleVersion')) {
                    continue
                }

                $moduleVersion = New-Object -TypeName System.Version -ArgumentList ([string] $manifestData.ModuleVersion)
                $packages += [pscustomobject]@{
                    Name            = $moduleDirectory.Name
                    Version         = $moduleVersion
                    SourceDirectory = $manifest.Directory.FullName
                    ManifestName    = $manifest.Name
                }
            }
            catch {
                Write-Warning "Ignoring invalid module manifest '$($manifest.FullName)': $($_.Exception.Message)"
            }
        }
    }

    $latestPackages = foreach ($moduleGroup in $packages | Group-Object -Property Name) {
        $moduleGroup.Group |
            Sort-Object -Property Version -Descending |
            Select-Object -First 1
    }

    return @($latestPackages)
}

function Install-LocalPowerShellModule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Package,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $DestinationRoot
    )

    $moduleDestination = Join-Path -Path $DestinationRoot -ChildPath $Package.Name
    $versionDestination = Join-Path -Path $moduleDestination -ChildPath $Package.Version.ToString()
    $sourcePath = [System.IO.Path]::GetFullPath($Package.SourceDirectory)
    $destinationPath = [System.IO.Path]::GetFullPath($versionDestination)

    if ($sourcePath -ieq $destinationPath) {
        $status = 'Already installed'
    }
    else {
        $status = if (Test-Path -LiteralPath $versionDestination -PathType Container) {
            'Updated'
        }
        else {
            'Installed'
        }

        $null = New-Item -Path $versionDestination -ItemType Directory -Force
        Get-ChildItem -LiteralPath $Package.SourceDirectory -Force |
            Copy-Item -Destination $versionDestination -Recurse -Force
    }

    $installedManifest = Join-Path -Path $versionDestination -ChildPath $Package.ManifestName
    if (-not (Test-Path -LiteralPath $installedManifest -PathType Leaf)) {
        Write-Error -Message "The module manifest was not installed correctly: $installedManifest"
    }

    $installedData = Import-PowerShellDataFile -Path $installedManifest
    if ([string] $installedData.ModuleVersion -ne $Package.Version.ToString()) {
        Write-Error -Message "The installed version of $($Package.Name) could not be verified."
    }

    [pscustomobject]@{
        Type    = 'PowerShell module'
        Name    = $Package.Name
        Version = $Package.Version.ToString()
        Status  = $status
        Path    = $versionDestination
    }
}

try {
    if ([string]::IsNullOrWhiteSpace($PackagePath)) {
        $nestedPackagePath = Join-Path -Path $PSScriptRoot -ChildPath 'VSCode-Packages'
        $hasDirectPackageFolders =
            (Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Extensions') -PathType Container) -or
            (Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath 'Modules') -PathType Container)

        if (Test-Path -LiteralPath $nestedPackagePath -PathType Container) {
            $PackagePath = $nestedPackagePath
        }
        elseif ($hasDirectPackageFolders) {
            $PackagePath = $PSScriptRoot
        }
        else {
            Write-Error -Message "No package directory was found beside the script. Pass its path with -PackagePath."
        }
    }

    $resolvedPackagePath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PackagePath)
    if (-not (Test-Path -LiteralPath $resolvedPackagePath -PathType Container)) {
        Write-Error -Message "The package directory does not exist: $resolvedPackagePath"
    }

    if ([string]::IsNullOrWhiteSpace($ModuleInstallPath)) {
        $documentsPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        $powerShellFolder = if ($PSVersionTable.PSEdition -eq 'Desktop') { 'WindowsPowerShell' } else { 'PowerShell' }
        $ModuleInstallPath = Join-Path -Path $documentsPath -ChildPath (Join-Path -Path $powerShellFolder -ChildPath 'Modules')
    }

    $resolvedModuleInstallPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ModuleInstallPath)
    $vsixFiles = @(Get-ChildItem -LiteralPath $resolvedPackagePath -Filter '*.vsix' -File -Recurse)
    $modulePackagePath = Join-Path -Path $resolvedPackagePath -ChildPath 'Modules'
    $modulePackages = @(Get-PowerShellModulePackage -Path $modulePackagePath)

    if (($vsixFiles.Count -eq 0) -and ($modulePackages.Count -eq 0)) {
        Write-Error -Message "No VSIX files or saved PowerShell modules were found under: $resolvedPackagePath"
    }

    $results = @()
    $failures = New-Object -TypeName 'System.Collections.Generic.List[string]'

    if ($vsixFiles.Count -gt 0) {
        $resolvedCodePath = Resolve-CodeCommand -RequestedPath $CodePath
        $vsixPackages = foreach ($vsixFile in $vsixFiles) {
            Read-VsixManifest -Path $vsixFile.FullName
        }

        foreach ($vsixPackage in Resolve-VsixDependencyOrder -Package $vsixPackages) {
            Write-Information -InformationAction Continue -MessageData "Installing VS Code extension $($vsixPackage.ExtensionId) $($vsixPackage.Version) ..."
            $commandOutput = @(& $resolvedCodePath --install-extension $vsixPackage.Path --force 2>&1)

            foreach ($outputLine in $commandOutput) {
                Write-Information -InformationAction Continue -MessageData ([string] $outputLine)
            }

            if ($LASTEXITCODE -eq 0) {
                $results += [pscustomobject]@{
                    Type    = 'VS Code extension'
                    Name    = $vsixPackage.ExtensionId
                    Version = $vsixPackage.Version
                    Status  = 'Installed'
                    Path    = $vsixPackage.Path
                }
            }
            else {
                $message = "VS Code could not install $($vsixPackage.ExtensionId). Exit code: $LASTEXITCODE"
                $failures.Add($message)
                Write-Error -Message $message -ErrorAction Continue
            }
        }
    }

    if ($modulePackages.Count -gt 0) {
        $null = New-Item -Path $resolvedModuleInstallPath -ItemType Directory -Force

        foreach ($modulePackage in $modulePackages) {
            try {
                Write-Information -InformationAction Continue -MessageData "Installing PowerShell module $($modulePackage.Name) $($modulePackage.Version) ..."
                $results += Install-LocalPowerShellModule -Package $modulePackage -DestinationRoot $resolvedModuleInstallPath
            }
            catch {
                $message = "PowerShell module $($modulePackage.Name) could not be installed: $($_.Exception.Message)"
                $failures.Add($message)
                Write-Error -Message $message -ErrorAction Continue
            }
        }
    }

    Write-Information -InformationAction Continue -MessageData ''
    $results | Format-Table -AutoSize

    if ($failures.Count -gt 0) {
        Write-Error -Message "$($failures.Count) package installation(s) failed."
        exit 1
    }
}
catch {
    Write-Error -ErrorRecord $_
    exit 1
}

exit 0
