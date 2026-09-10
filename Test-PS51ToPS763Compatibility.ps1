#requires -Version 5.1

<#
.SYNOPSIS
Audits a script for migration from Windows PowerShell 5.1 to PowerShell 7.6.3.

.DESCRIPTION
The supplied script is parsed but never executed. The auditor launches clean child
processes for Windows PowerShell 5.1 and PowerShell 7, inventories their environments
and compares parsing, commands, parameters, modules, profiles and known compatibility
risks. Literal local dot-sourced scripts and path-based module dependencies are also
parsed when they can be resolved without executing the supplied code.

The report separates blocking findings, warnings and items needing a controlled
runtime test. Static analysis cannot prove every possible runtime path, external
dependency or dynamically constructed command.

.PARAMETER ScriptPath
The .ps1, .psm1 or .psd1 file to audit.

.PARAMETER PowerShell7Path
Path or command name for the target pwsh.exe. The default is pwsh.exe.

.PARAMETER WindowsPowerShellPath
Path to Windows PowerShell 5.1. The default is the standard Windows location.

.PARAMETER TargetPowerShellVersion
Exact target version. The default is 7.6.3.

.PARAMETER OutputDirectory
Directory for the Markdown, JSON and CSV reports. A timestamped directory in the
current directory is used by default.

.PARAMETER IncludeProfileSessions
Also starts each shell with its normal profiles enabled. Profiles themselves can run
arbitrary user code, so this is opt-in. Profile files are inspected statically even
when this switch is not used.

.PARAMETER AllowTargetVersionMismatch
Treats an installed pwsh patch-version mismatch as a warning rather than a blocker.
The report still states the actual version used and cannot certify the requested one.

.EXAMPLE
.\Test-PS51ToPS763Compatibility.ps1 -ScriptPath C:\Scripts\Job.ps1

.EXAMPLE
.\Test-PS51ToPS763Compatibility.ps1 -ScriptPath C:\Scripts\Job.ps1 -IncludeProfileSessions

.NOTES
Exit code 0 means that the audit completed with no blocking findings. Exit code 1
means that the audit failed or at least one blocking finding was detected. Warnings
and manual-review findings do not change the exit code.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ScriptPath,

    [string]$PowerShell7Path = 'pwsh.exe',

    [string]$WindowsPowerShellPath = $(
        if ($env:WINDIR) {
            Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        }
        else {
            'powershell.exe'
        }
    ),

    [version]$TargetPowerShellVersion = '7.6.3',

    [string]$OutputDirectory,

    [switch]$IncludeProfileSessions,

    [switch]$AllowTargetVersionMismatch
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-ExecutablePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Path).ProviderPath
    }

    $command = Get-Command -Name $Path -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }

    return $null
}

function Add-Finding {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.ArrayList]$List,
        [Parameter(Mandatory = $true)][ValidateSet('BLOCKER', 'WARNING', 'REVIEW', 'INFO')][string]$Severity,
        [Parameter(Mandatory = $true)][string]$Category,
        [string]$File,
        [int]$Line,
        [string]$Item,
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Evidence51,
        [string]$Evidence76,
        [string]$Recommendation
    )

    [void]$List.Add([pscustomobject][ordered]@{
        Severity       = $Severity
        Category       = $Category
        File           = $File
        Line           = $Line
        Item           = $Item
        Message        = $Message
        Evidence51     = $Evidence51
        Evidence76     = $Evidence76
        Recommendation = $Recommendation
    })
}

function ConvertTo-DisplayText {
    param($Value)

    if ($null -eq $Value) {
        return ''
    }
    if ($Value -is [System.Array]) {
        return (($Value | ForEach-Object { [string]$_ }) -join ', ')
    }
    return [string]$Value
}

function Escape-MarkdownCell {
    param($Value)

    $text = ConvertTo-DisplayText $Value
    $text = $text -replace '\|', '\|'
    $text = $text -replace "`r?`n", '<br>'
    return $text
}

function Get-CommandKey {
    param($CommandRecord)

    return ('{0}|{1}|{2}|{3}' -f $CommandRecord.File, $CommandRecord.Line,
        $CommandRecord.Column, ([string]$CommandRecord.Name).ToLowerInvariant())
}

function Get-NormalizedPathKey {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ''
    }
    return $Path.TrimEnd([char[]]@('\', '/')).ToLowerInvariant()
}

function Get-HighestModule {
    param(
        [object[]]$Modules,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return @($Modules | Where-Object { $_.Name -ieq $Name } |
        Sort-Object { try { [version]$_.Version } catch { [version]'0.0' } } -Descending)[0]
}

function Invoke-Probe {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$ProbePath,
        [Parameter(Mandatory = $true)][string]$InputScriptPath,
        [Parameter(Mandatory = $true)][string]$ResultPath,
        [switch]$LoadProfiles
    )

    $arguments = @('-NoLogo')
    if (-not $LoadProfiles) {
        $arguments += '-NoProfile'
    }
    $arguments += @(
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File', $ProbePath,
        '-ScriptPath', $InputScriptPath,
        '-OutputPath', $ResultPath
    )

    $probeOutput = @(& $Executable @arguments 2>&1 | ForEach-Object { [string]$_ })
    $probeExitCode = $LASTEXITCODE

    if (($probeExitCode -ne 0) -or -not (Test-Path -LiteralPath $ResultPath -PathType Leaf)) {
        $detail = $probeOutput -join [Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = 'The child process returned no diagnostic output.'
        }
        Write-Error ("Probe failed for {0} with exit code {1}. {2}" -f $Executable, $probeExitCode, $detail)
    }

    return (Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json)
}

function Write-MarkdownReport {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('# Windows PowerShell 5.1 to PowerShell {0} compatibility audit' -f $Report.RequestedTargetVersion))
    $lines.Add('')
    $lines.Add(('Generated: {0}' -f $Report.GeneratedAt))
    $lines.Add('')
    $lines.Add(('Supplied script: `{0}`' -f $Report.ScriptPath))
    $lines.Add('')
    $lines.Add(('Audited target: PowerShell {0}' -f $Report.RequestedTargetVersion))
    $lines.Add('')
    $lines.Add('## Result')
    $lines.Add('')
    $lines.Add(('Blocking findings: **{0}**  ' -f $Report.Summary.Blockers))
    $lines.Add(('Warnings: **{0}**  ' -f $Report.Summary.Warnings))
    $lines.Add(('Manual-review findings: **{0}**  ' -f $Report.Summary.Review))
    $lines.Add(('Information findings: **{0}**' -f $Report.Summary.Information))
    $lines.Add('')
    $lines.Add($Report.Summary.Conclusion)
    $lines.Add('')
    $lines.Add('## Scope and limits')
    $lines.Add('')
    $lines.Add('The supplied script and statically resolvable local dependencies were parsed but not executed. Installed module discovery and command metadata were inspected in child shell processes. Profile files were parsed without execution unless `-IncludeProfileSessions` was supplied.')
    $lines.Add('')
    $lines.Add('This audit cannot prove all runtime behaviour. Dynamic command construction, data-dependent branches, external services, permissions, credentials, remoting endpoints, native executables and code executed inside imported modules require a controlled runtime test using representative inputs and the real execution identity.')
    $lines.Add('')
    $lines.Add('## Environment comparison')
    $lines.Add('')
    $lines.Add('| Property | Windows PowerShell 5.1 | PowerShell target |')
    $lines.Add('|---|---|---|')
    $lines.Add(('| Version | {0} | {1} |' -f (Escape-MarkdownCell $Report.WindowsPowerShell.Version), (Escape-MarkdownCell $Report.PowerShell7.Version)))
    $lines.Add(('| Edition | {0} | {1} |' -f (Escape-MarkdownCell $Report.WindowsPowerShell.Edition), (Escape-MarkdownCell $Report.PowerShell7.Edition)))
    $lines.Add(('| Executable | {0} | {1} |' -f (Escape-MarkdownCell $Report.WindowsPowerShell.Executable), (Escape-MarkdownCell $Report.PowerShell7.Executable)))
    $lines.Add(('| Identity | {0} | {1} |' -f (Escape-MarkdownCell $Report.WindowsPowerShell.Identity), (Escape-MarkdownCell $Report.PowerShell7.Identity)))
    $lines.Add(('| SID | {0} | {1} |' -f (Escape-MarkdownCell $Report.WindowsPowerShell.Sid), (Escape-MarkdownCell $Report.PowerShell7.Sid)))
    $lines.Add(('| Process bitness | {0} | {1} |' -f (Escape-MarkdownCell $Report.WindowsPowerShell.Bitness), (Escape-MarkdownCell $Report.PowerShell7.Bitness)))
    $lines.Add(('| Language mode | {0} | {1} |' -f (Escape-MarkdownCell $Report.WindowsPowerShell.LanguageMode), (Escape-MarkdownCell $Report.PowerShell7.LanguageMode)))
    $lines.Add(('| Culture | {0} | {1} |' -f (Escape-MarkdownCell $Report.WindowsPowerShell.Culture), (Escape-MarkdownCell $Report.PowerShell7.Culture)))
    $lines.Add(('| Available module names | {0} | {1} |' -f $Report.WindowsPowerShell.AvailableModuleNameCount, $Report.PowerShell7.AvailableModuleNameCount))
    $lines.Add('')
    $lines.Add('## Findings')
    $lines.Add('')

    if (@($Report.Findings).Count -eq 0) {
        $lines.Add('No findings were produced.')
    }
    else {
        $lines.Add('| Severity | Category | Location | Item | Finding | Recommendation |')
        $lines.Add('|---|---|---|---|---|---|')
        foreach ($finding in @($Report.Findings)) {
            $location = ''
            if ($finding.File) {
                $location = $finding.File
                if ($finding.Line -gt 0) {
                    $location = '{0}:{1}' -f $location, $finding.Line
                }
            }
            $lines.Add(('| {0} | {1} | {2} | {3} | {4} | {5} |' -f
                (Escape-MarkdownCell $finding.Severity),
                (Escape-MarkdownCell $finding.Category),
                (Escape-MarkdownCell $location),
                (Escape-MarkdownCell $finding.Item),
                (Escape-MarkdownCell $finding.Message),
                (Escape-MarkdownCell $finding.Recommendation)))
        }
    }

    $lines.Add('')
    $lines.Add('## Parsed files')
    $lines.Add('')
    foreach ($file in @($Report.ParsedFiles | Sort-Object Path -Unique)) {
        $lines.Add(('- `{0}`' -f $file.Path))
    }
    $lines.Add('')
    $lines.Add('## Output files')
    $lines.Add('')
    $lines.Add('- This Markdown report')
    $lines.Add('- `compatibility-audit.json`: full evidence and environment snapshots')
    $lines.Add('- `compatibility-findings.csv`: filterable findings')
    $lines.Add('- `module-comparison.csv`: module-name and highest-version comparison')

    $lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

$resolvedScriptPath = (Resolve-Path -LiteralPath $ScriptPath).ProviderPath

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-Location).ProviderPath (
        'PS51-to-PS763-Audit-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}

if (-not (Test-Path -LiteralPath $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).ProviderPath

$windowsPowerShellExe = Resolve-ExecutablePath -Path $WindowsPowerShellPath
$powerShell7Exe = Resolve-ExecutablePath -Path $PowerShell7Path

if (-not $windowsPowerShellExe) {
    Write-Error ("Windows PowerShell executable was not found: {0}" -f $WindowsPowerShellPath)
    exit 1
}
if (-not $powerShell7Exe) {
    Write-Error ("PowerShell 7 executable was not found: {0}" -f $PowerShell7Path)
    exit 1
}

$probeSource = @'
#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$probeErrors = New-Object System.Collections.ArrayList

function Get-StaticText {
    param(
        $Ast,
        [string]$ContainingFile
    )

    if ($Ast -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Ast.Value
    }
    if ($Ast -is [System.Management.Automation.Language.ExpandableStringExpressionAst]) {
        $supported = $true
        foreach ($nestedExpression in @($Ast.NestedExpressions)) {
            if ($nestedExpression -isnot [System.Management.Automation.Language.VariableExpressionAst] -or
                $nestedExpression.VariablePath.UserPath -notin @('PSScriptRoot', 'PSCommandPath')) {
                $supported = $false
                break
            }
        }
        if ($supported) {
            $value = $Ast.Value
            if (-not [string]::IsNullOrWhiteSpace($ContainingFile)) {
                $scriptRoot = Split-Path -Parent $ContainingFile
                $value = $value.Replace('${PSScriptRoot}', $scriptRoot)
                $value = $value.Replace('$PSScriptRoot', $scriptRoot)
                $value = $value.Replace('${PSCommandPath}', $ContainingFile)
                $value = $value.Replace('$PSCommandPath', $ContainingFile)
            }
            return $value
        }
    }
    if ($Ast -is [System.Management.Automation.Language.VariableExpressionAst] -and
        -not [string]::IsNullOrWhiteSpace($ContainingFile)) {
        if ($Ast.VariablePath.UserPath -eq 'PSScriptRoot') {
            return (Split-Path -Parent $ContainingFile)
        }
        if ($Ast.VariablePath.UserPath -eq 'PSCommandPath') {
            return $ContainingFile
        }
    }
    if ($Ast -is [System.Management.Automation.Language.ConstantExpressionAst] -and
        $null -ne $Ast.Value) {
        return [string]$Ast.Value
    }
    return $null
}

function Resolve-LocalReference {
    param(
        [Parameter(Mandatory = $true)][string]$Reference,
        [Parameter(Mandatory = $true)][string]$ContainingFile
    )

    $candidate = [Environment]::ExpandEnvironmentVariables($Reference)
    if (-not [IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path (Split-Path -Parent $ContainingFile) $candidate
    }

    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        return (Resolve-Path -LiteralPath $candidate).ProviderPath
    }

    if (Test-Path -LiteralPath $candidate -PathType Container) {
        $leaf = Split-Path -Leaf $candidate
        $manifest = Join-Path $candidate ($leaf + '.psd1')
        $module = Join-Path $candidate ($leaf + '.psm1')
        if (Test-Path -LiteralPath $manifest -PathType Leaf) {
            return (Resolve-Path -LiteralPath $manifest).ProviderPath
        }
        if (Test-Path -LiteralPath $module -PathType Leaf) {
            return (Resolve-Path -LiteralPath $module).ProviderPath
        }
    }

    return $null
}

function Get-ProfileRecord {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [string]$Path
    )

    $exists = $false
    $hash = $null
    $imports = @()
    $parseErrorText = @()

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        $exists = Test-Path -LiteralPath $Path -PathType Leaf
    }

    if ($exists) {
        try {
            $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $Path, [ref]$tokens, [ref]$parseErrors)
            $parseErrorText = @($parseErrors | ForEach-Object { $_.Message })
            $importCommands = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -ieq 'Import-Module'
            }, $true))
            foreach ($command in $importCommands) {
                foreach ($element in @($command.CommandElements | Select-Object -Skip 1)) {
                    $value = Get-StaticText -Ast $element -ContainingFile $Path
                    if (-not [string]::IsNullOrWhiteSpace($value) -and -not $value.StartsWith('-')) {
                        $imports += $value
                        break
                    }
                }
            }
        }
        catch {
            $parseErrorText += $_.Exception.Message
        }
    }

    return [pscustomobject][ordered]@{
        Kind                = $Kind
        Path                = $Path
        Exists              = $exists
        Sha256              = $hash
        StaticModuleImports = @($imports | Sort-Object -Unique)
        ParseErrors         = @($parseErrorText)
    }
}

try {
    $identityName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
    $identitySid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}
catch {
    $identityName = [Environment]::UserName
    $identitySid = $null
}

$executionPolicies = @()
try {
    $executionPolicies = @(Get-ExecutionPolicy -List | ForEach-Object {
        [pscustomobject]@{ Scope = [string]$_.Scope; Policy = [string]$_.ExecutionPolicy }
    })
}
catch {
    [void]$probeErrors.Add(('Execution policy inventory: ' + $_.Exception.Message))
}

$profileRecords = @()
foreach ($kind in @('AllUsersAllHosts', 'AllUsersCurrentHost', 'CurrentUserAllHosts', 'CurrentUserCurrentHost')) {
    $profilePath = $null
    try { $profilePath = [string]$PROFILE.$kind } catch { }
    $profileRecords += Get-ProfileRecord -Kind $kind -Path $profilePath
}

$availableModules = @()
$moduleCommandIndex = @{}
try {
    foreach ($module in @(Get-Module -ListAvailable)) {
        $editions = @($module.CompatiblePSEditions | ForEach-Object { [string]$_ })
        $editionCompatible = $true
        if ($editions.Count -gt 0 -and $editions -notcontains [string]$PSVersionTable.PSEdition) {
            $editionCompatible = $false
        }

        $moduleRecord = [pscustomobject][ordered]@{
            Name                   = $module.Name
            Version                = [string]$module.Version
            ModuleType             = [string]$module.ModuleType
            Path                   = $module.Path
            ModuleBase             = $module.ModuleBase
            CompatiblePSEditions   = $editions
            EditionCompatible      = $editionCompatible
            Guid                   = [string]$module.Guid
            PowerShellVersion      = [string]$module.PowerShellVersion
            DotNetFrameworkVersion = [string]$module.DotNetFrameworkVersion
            ClrVersion             = [string]$module.ClrVersion
            ProcessorArchitecture  = [string]$module.ProcessorArchitecture
        }
        $availableModules += $moduleRecord

        try {
            foreach ($exportedName in @($module.ExportedCommands.Keys)) {
                $indexKey = ([string]$exportedName).ToLowerInvariant()
                if (-not $moduleCommandIndex.ContainsKey($indexKey)) {
                    $moduleCommandIndex[$indexKey] = New-Object System.Collections.ArrayList
                }
                [void]$moduleCommandIndex[$indexKey].Add([pscustomobject][ordered]@{
                    Name               = [string]$exportedName
                    ModuleName         = $module.Name
                    Version            = [string]$module.Version
                    Path               = $module.Path
                    CompatiblePSEditions = $editions
                    EditionCompatible  = $editionCompatible
                })
            }
        }
        catch {
            [void]$probeErrors.Add(('Module command metadata for {0}: {1}' -f $module.Name, $_.Exception.Message))
        }
    }
}
catch {
    [void]$probeErrors.Add(('Available module inventory: ' + $_.Exception.Message))
}

$loadedModules = @()
try {
    $loadedModules = @(Get-Module | ForEach-Object {
        [pscustomobject][ordered]@{
            Name    = $_.Name
            Version = [string]$_.Version
            Path    = $_.Path
        }
    })
}
catch {
    [void]$probeErrors.Add(('Loaded module inventory: ' + $_.Exception.Message))
}

$registeredSnapIns = @()
if (Get-Command -Name Get-PSSnapin -ErrorAction SilentlyContinue) {
    try {
        $registeredSnapIns = @(Get-PSSnapin -Registered | ForEach-Object {
            [pscustomobject][ordered]@{
                Name    = $_.Name
                Version = [string]$_.Version
            }
        })
    }
    catch {
        [void]$probeErrors.Add(('Registered snap-in inventory: ' + $_.Exception.Message))
    }
}

$queue = New-Object System.Collections.Queue
$queue.Enqueue((Resolve-Path -LiteralPath $ScriptPath).ProviderPath)
$visited = @{}
$parsedFiles = New-Object System.Collections.ArrayList
$commandOccurrences = New-Object System.Collections.ArrayList
$moduleReferences = New-Object System.Collections.ArrayList
$typeReferences = New-Object System.Collections.ArrayList
$variableReferences = New-Object System.Collections.ArrayList
$localFunctions = @{}

while ($queue.Count -gt 0) {
    $currentFile = [string]$queue.Dequeue()
    $visitKey = $currentFile.ToLowerInvariant()
    if ($visited.ContainsKey($visitKey)) {
        continue
    }
    $visited[$visitKey] = $true

    $tokens = $null
    $parseErrors = $null
    $ast = $null
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $currentFile, [ref]$tokens, [ref]$parseErrors)
    }
    catch {
        [void]$parsedFiles.Add([pscustomobject][ordered]@{
            Path                  = $currentFile
            Sha256                = $null
            ParseErrors           = @([pscustomobject][ordered]@{
                Message = $_.Exception.Message
                Line    = 0
                Column  = 0
                Text    = ''
            })
            RequiredPSVersion     = ''
            RequiredPSEditions    = @()
            RequiredAssemblies    = @()
            RequiredApplicationId = ''
            IsElevationRequired   = $false
        })
        continue
    }

    $fileHash = $null
    try { $fileHash = (Get-FileHash -LiteralPath $currentFile -Algorithm SHA256).Hash } catch { }
    [void]$parsedFiles.Add([pscustomobject][ordered]@{
        Path   = $currentFile
        Sha256 = $fileHash
        ParseErrors = @($parseErrors | ForEach-Object {
            [pscustomobject][ordered]@{
                Message = $_.Message
                Line    = $_.Extent.StartLineNumber
                Column  = $_.Extent.StartColumnNumber
                Text    = $_.Extent.Text
            }
        })
        RequiredPSVersion    = $(if ($ast.ScriptRequirements) { [string]$ast.ScriptRequirements.RequiredPSVersion } else { '' })
        RequiredPSEditions   = $(if ($ast.ScriptRequirements) { @($ast.ScriptRequirements.RequiredPSEditions | ForEach-Object { [string]$_ }) } else { @() })
        RequiredAssemblies   = $(if ($ast.ScriptRequirements) { @($ast.ScriptRequirements.RequiredAssemblies | ForEach-Object { [string]$_ }) } else { @() })
        RequiredApplicationId = $(if ($ast.ScriptRequirements) { [string]$ast.ScriptRequirements.RequiredApplicationId } else { '' })
        IsElevationRequired  = $(if ($ast.ScriptRequirements) { [bool]$ast.ScriptRequirements.IsElevationRequired } else { $false })
    })

    if ([IO.Path]::GetExtension($currentFile) -ieq '.psd1') {
        try {
            $manifestData = Import-PowerShellDataFile -LiteralPath $currentFile
            foreach ($manifestCodeKey in @('RootModule', 'NestedModules', 'ScriptsToProcess')) {
                foreach ($manifestCodeEntry in @($manifestData[$manifestCodeKey])) {
                    if ($manifestCodeEntry -isnot [string] -or [string]::IsNullOrWhiteSpace($manifestCodeEntry)) {
                        continue
                    }
                    $manifestCodePath = Resolve-LocalReference -Reference $manifestCodeEntry -ContainingFile $currentFile
                    if ($manifestCodePath -and ([IO.Path]::GetExtension($manifestCodePath) -in @('.ps1', '.psm1', '.psd1'))) {
                        $queue.Enqueue($manifestCodePath)
                    }
                }
            }

            foreach ($requiredManifestModule in @($manifestData['RequiredModules'])) {
                $manifestModuleName = ''
                $manifestRequiredVersion = ''
                $manifestMinimumVersion = ''
                $manifestMaximumVersion = ''
                $manifestGuid = ''
                if ($requiredManifestModule -is [string]) {
                    $manifestModuleName = $requiredManifestModule
                }
                elseif ($requiredManifestModule -is [System.Collections.IDictionary]) {
                    $manifestModuleName = [string]$requiredManifestModule['ModuleName']
                    $manifestRequiredVersion = [string]$requiredManifestModule['RequiredVersion']
                    $manifestMinimumVersion = [string]$requiredManifestModule['ModuleVersion']
                    $manifestMaximumVersion = [string]$requiredManifestModule['MaximumVersion']
                    $manifestGuid = [string]$requiredManifestModule['Guid']
                }

                if (-not [string]::IsNullOrWhiteSpace($manifestModuleName)) {
                    [void]$moduleReferences.Add([pscustomobject][ordered]@{
                        File            = $currentFile
                        Line            = 1
                        Kind            = 'ManifestRequiredModule'
                        Name            = $manifestModuleName
                        RequiredVersion = $manifestRequiredVersion
                        MinimumVersion  = $manifestMinimumVersion
                        MaximumVersion  = $manifestMaximumVersion
                        Guid            = $manifestGuid
                        ResolvedPath    = $null
                    })
                }
            }
        }
        catch {
            [void]$probeErrors.Add(('Module manifest inspection for {0}: {1}' -f $currentFile, $_.Exception.Message))
        }
    }

    foreach ($functionAst in @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
    }, $true))) {
        $localFunctions[$functionAst.Name.ToLowerInvariant()] = $true
    }

    foreach ($typeAst in @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.TypeExpressionAst]
    }, $true))) {
        [void]$typeReferences.Add([pscustomobject][ordered]@{
            File   = $currentFile
            Line   = $typeAst.Extent.StartLineNumber
            Column = $typeAst.Extent.StartColumnNumber
            Name   = $typeAst.TypeName.FullName
            Text   = $typeAst.Extent.Text
        })
    }

    foreach ($variableAst in @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true))) {
        [void]$variableReferences.Add([pscustomobject][ordered]@{
            File   = $currentFile
            Line   = $variableAst.Extent.StartLineNumber
            Column = $variableAst.Extent.StartColumnNumber
            Name   = $variableAst.VariablePath.UserPath
            Text   = $variableAst.Extent.Text
        })
    }

    if ($ast.ScriptRequirements) {
        foreach ($requiredModule in @($ast.ScriptRequirements.RequiredModules)) {
            [void]$moduleReferences.Add([pscustomobject][ordered]@{
                File            = $currentFile
                Line            = 1
                Kind            = 'Requires'
                Name            = [string]$requiredModule.Name
                RequiredVersion = [string]$requiredModule.RequiredVersion
                MinimumVersion  = [string]$requiredModule.Version
                MaximumVersion  = [string]$requiredModule.MaximumVersion
                Guid            = [string]$requiredModule.Guid
                ResolvedPath    = $null
            })
        }
    }

    foreach ($usingAst in @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.UsingStatementAst]
    }, $true))) {
        if ([string]$usingAst.UsingStatementKind -ne 'Module') {
            continue
        }
        $usingName = $usingAst.Name.Extent.Text.Trim('"', "'")
        $usingPath = Resolve-LocalReference -Reference $usingName -ContainingFile $currentFile
        [void]$moduleReferences.Add([pscustomobject][ordered]@{
            File            = $currentFile
            Line            = $usingAst.Extent.StartLineNumber
            Kind            = 'Using'
            Name            = $usingName
            RequiredVersion = ''
            MinimumVersion  = ''
            MaximumVersion  = ''
            Guid            = ''
            ResolvedPath    = $usingPath
        })
        if ($usingPath -and ([IO.Path]::GetExtension($usingPath) -in @('.ps1', '.psm1', '.psd1'))) {
            $queue.Enqueue($usingPath)
        }
    }

    foreach ($commandAst in @($ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst]
    }, $true))) {
        $commandName = $commandAst.GetCommandName()
        if ([string]::IsNullOrWhiteSpace($commandName) -and
            [string]$commandAst.InvocationOperator -in @('Dot', 'Ampersand') -and
            @($commandAst.CommandElements).Count -gt 0) {
            $commandName = Get-StaticText -Ast $commandAst.CommandElements[0] -ContainingFile $currentFile
        }
        $parametersUsed = @($commandAst.CommandElements |
            Where-Object { $_ -is [System.Management.Automation.Language.CommandParameterAst] } |
            ForEach-Object { $_.ParameterName })
        $literalArguments = @()
        foreach ($element in @($commandAst.CommandElements | Select-Object -Skip 1)) {
            $staticValue = Get-StaticText -Ast $element -ContainingFile $currentFile
            if ($null -ne $staticValue) {
                $literalArguments += $staticValue
            }
        }

        [void]$commandOccurrences.Add([pscustomobject][ordered]@{
            File             = $currentFile
            Line             = $commandAst.Extent.StartLineNumber
            Column           = $commandAst.Extent.StartColumnNumber
            Name             = $commandName
            InvocationOperator = [string]$commandAst.InvocationOperator
            ParametersUsed   = @($parametersUsed)
            LiteralArguments = @($literalArguments)
            Text             = $commandAst.Extent.Text
        })

        if ($commandName -ieq 'Import-Module') {
            $moduleName = $null
            $requiredVersion = ''
            $minimumVersion = ''
            $maximumVersion = ''
            $guid = ''
            $pendingModuleArgument = ''
            foreach ($element in @($commandAst.CommandElements | Select-Object -Skip 1)) {
                if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                    switch ($element.ParameterName) {
                        'Name'           { $pendingModuleArgument = 'Name' }
                        'RequiredVersion'{ $pendingModuleArgument = 'RequiredVersion' }
                        'Version'        { $pendingModuleArgument = 'MinimumVersion' }
                        'MinimumVersion' { $pendingModuleArgument = 'MinimumVersion' }
                        'MaximumVersion' { $pendingModuleArgument = 'MaximumVersion' }
                        'Guid'           { $pendingModuleArgument = 'Guid' }
                        default          { $pendingModuleArgument = '' }
                    }
                    continue
                }

                $moduleValue = Get-StaticText -Ast $element -ContainingFile $currentFile
                if ($null -eq $moduleValue) {
                    $pendingModuleArgument = ''
                    continue
                }

                switch ($pendingModuleArgument) {
                    'Name'            { $moduleName = $moduleValue }
                    'RequiredVersion' { $requiredVersion = $moduleValue }
                    'MinimumVersion'  { $minimumVersion = $moduleValue }
                    'MaximumVersion'  { $maximumVersion = $moduleValue }
                    'Guid'            { $guid = $moduleValue }
                    default {
                        if (-not $moduleName) {
                            $moduleName = $moduleValue
                        }
                    }
                }
                $pendingModuleArgument = ''
            }
            if ($moduleName) {
                $resolvedModulePath = Resolve-LocalReference -Reference $moduleName -ContainingFile $currentFile
                [void]$moduleReferences.Add([pscustomobject][ordered]@{
                    File            = $currentFile
                    Line            = $commandAst.Extent.StartLineNumber
                    Kind            = 'ImportModule'
                    Name            = [string]$moduleName
                    RequiredVersion = [string]$requiredVersion
                    MinimumVersion  = [string]$minimumVersion
                    MaximumVersion  = [string]$maximumVersion
                    Guid            = [string]$guid
                    ResolvedPath    = $resolvedModulePath
                })
                if ($resolvedModulePath -and ([IO.Path]::GetExtension($resolvedModulePath) -in @('.ps1', '.psm1', '.psd1'))) {
                    $queue.Enqueue($resolvedModulePath)
                }
            }
        }

        if ([string]$commandAst.InvocationOperator -in @('Dot', 'Ampersand') -and $commandName) {
            $localReference = Resolve-LocalReference -Reference $commandName -ContainingFile $currentFile
            if ($localReference -and ([IO.Path]::GetExtension($localReference) -in @('.ps1', '.psm1', '.psd1'))) {
                $queue.Enqueue($localReference)
            }
        }
    }
}

$resolvedCommands = @()
$autoLoadingVariable = Get-Variable -Name PSModuleAutoLoadingPreference -ErrorAction SilentlyContinue
$hadAutoLoadingPreference = $null -ne $autoLoadingVariable
$oldAutoLoadingPreference = $null
if ($hadAutoLoadingPreference) {
    $oldAutoLoadingPreference = $autoLoadingVariable.Value
}
$PSModuleAutoLoadingPreference = 'None'
try {
    foreach ($occurrence in @($commandOccurrences)) {
        $name = [string]$occurrence.Name
        $found = $false
        $resolutionKind = 'NotFound'
        $commandType = ''
        $source = ''
        $version = ''
        $definition = ''
        $parameterNames = @()
        $editionCompatible = $true
        $candidates = @()

        if ([string]::IsNullOrWhiteSpace($name)) {
            $resolutionKind = 'Dynamic'
        }
        elseif ($localFunctions.ContainsKey($name.ToLowerInvariant())) {
            $found = $true
            $resolutionKind = 'LocalScript'
            $commandType = 'Function'
            $source = 'Supplied script or local dependency'
        }
        else {
            $commandInfo = @(Get-Command -Name $name -All -ErrorAction SilentlyContinue) |
                Select-Object -First 1
            if ($commandInfo) {
                $found = $true
                $resolutionKind = 'SessionCommand'
                $commandType = [string]$commandInfo.CommandType
                $source = [string]$commandInfo.Source
                $version = [string]$commandInfo.Version
                $definition = [string]$commandInfo.Definition
                try {
                    foreach ($parameter in $commandInfo.Parameters.GetEnumerator()) {
                        $parameterNames += [string]$parameter.Key
                        $parameterNames += @($parameter.Value.Aliases | ForEach-Object { [string]$_ })
                    }
                    $parameterNames = @($parameterNames | Sort-Object -Unique)
                }
                catch { }
            }
            else {
                $indexKey = $name.ToLowerInvariant()
                if ($moduleCommandIndex.ContainsKey($indexKey)) {
                    $candidates = @($moduleCommandIndex[$indexKey])
                    $selectedCandidate = @($candidates | Where-Object { $_.EditionCompatible } |
                        Sort-Object { try { [version]$_.Version } catch { [version]'0.0' } } -Descending |
                        Select-Object -First 1)
                    if ($selectedCandidate.Count -eq 0) {
                        $selectedCandidate = @($candidates | Select-Object -First 1)
                    }
                    if ($selectedCandidate.Count -gt 0) {
                        $found = $true
                        $resolutionKind = 'AvailableModule'
                        $commandType = 'ModuleExport'
                        $source = $selectedCandidate[0].ModuleName
                        $version = $selectedCandidate[0].Version
                        $editionCompatible = [bool]$selectedCandidate[0].EditionCompatible
                    }
                }
            }
        }

        $resolvedCommands += [pscustomobject][ordered]@{
            File               = $occurrence.File
            Line               = $occurrence.Line
            Column             = $occurrence.Column
            Name               = $occurrence.Name
            InvocationOperator = $occurrence.InvocationOperator
            ParametersUsed     = @($occurrence.ParametersUsed)
            LiteralArguments   = @($occurrence.LiteralArguments)
            Text               = $occurrence.Text
            Found              = $found
            ResolutionKind     = $resolutionKind
            CommandType        = $commandType
            Source             = $source
            Version            = $version
            Definition         = $definition
            AvailableParameters = @($parameterNames)
            EditionCompatible  = $editionCompatible
            ModuleCandidates   = @($candidates)
        }
    }
}
finally {
    if ($hadAutoLoadingPreference) {
        $PSModuleAutoLoadingPreference = $oldAutoLoadingPreference
    }
    else {
        Remove-Variable -Name PSModuleAutoLoadingPreference -ErrorAction SilentlyContinue
    }
}

$safeEnvironment = [ordered]@{
    PATH                        = $env:PATH
    PATHEXT                     = $env:PATHEXT
    PSModulePath                = $env:PSModulePath
    PSExecutionPolicyPreference = $env:PSExecutionPolicyPreference
    TEMP                        = $env:TEMP
    TMP                         = $env:TMP
}

$result = [pscustomobject][ordered]@{
    CapturedAt       = (Get-Date).ToString('o')
    Version          = [string]$PSVersionTable.PSVersion
    Edition          = [string]$PSVersionTable.PSEdition
    GitCommitId      = [string]$PSVersionTable.GitCommitId
    Executable       = (Get-Process -Id $PID).Path
    PSHome           = $PSHOME
    Identity         = $identityName
    Sid              = $identitySid
    Is64BitProcess   = [Environment]::Is64BitProcess
    Is64BitOS        = [Environment]::Is64BitOperatingSystem
    LanguageMode     = [string]$ExecutionContext.SessionState.LanguageMode
    Culture          = [Globalization.CultureInfo]::CurrentCulture.Name
    UICulture        = [Globalization.CultureInfo]::CurrentUICulture.Name
    CurrentDirectory = (Get-Location).ProviderPath
    HomeDirectory    = $HOME
    DocumentsDirectory = [Environment]::GetFolderPath('MyDocuments')
    ExecutionPolicies  = @($executionPolicies)
    SafeEnvironment    = $safeEnvironment
    ModulePathEntries  = @($env:PSModulePath -split [IO.Path]::PathSeparator | ForEach-Object {
        [pscustomobject]@{ Path = $_; Exists = (Test-Path -LiteralPath $_ -PathType Container) }
    })
    Profiles            = @($profileRecords)
    AvailableModules    = @($availableModules)
    LoadedModules       = @($loadedModules)
    RegisteredSnapIns   = @($registeredSnapIns)
    ParsedFiles         = @($parsedFiles)
    Commands            = @($resolvedCommands)
    ModuleReferences    = @($moduleReferences)
    TypeReferences      = @($typeReferences)
    VariableReferences  = @($variableReferences)
    ProbeErrors         = @($probeErrors)
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
exit 0
'@

$probePath = Join-Path $OutputDirectory '_compatibility-probe.ps1'
$ps51ResultPath = Join-Path $OutputDirectory '_ps51.json'
$ps7ResultPath = Join-Path $OutputDirectory '_ps7.json'
$ps51ProfileResultPath = Join-Path $OutputDirectory '_ps51-profile.json'
$ps7ProfileResultPath = Join-Path $OutputDirectory '_ps7-profile.json'

$probeSource | Set-Content -LiteralPath $probePath -Encoding UTF8

try {
    $ps51 = Invoke-Probe -Executable $windowsPowerShellExe -ProbePath $probePath `
        -InputScriptPath $resolvedScriptPath -ResultPath $ps51ResultPath
    $ps7 = Invoke-Probe -Executable $powerShell7Exe -ProbePath $probePath `
        -InputScriptPath $resolvedScriptPath -ResultPath $ps7ResultPath

    $ps51Profile = $null
    $ps7Profile = $null
    if ($IncludeProfileSessions) {
        $ps51Profile = Invoke-Probe -Executable $windowsPowerShellExe -ProbePath $probePath `
            -InputScriptPath $resolvedScriptPath -ResultPath $ps51ProfileResultPath -LoadProfiles
        $ps7Profile = Invoke-Probe -Executable $powerShell7Exe -ProbePath $probePath `
            -InputScriptPath $resolvedScriptPath -ResultPath $ps7ProfileResultPath -LoadProfiles
    }
}
catch {
    Write-Error $_
    exit 1
}
finally {
    Remove-Item -LiteralPath $probePath -Force -ErrorAction SilentlyContinue
}

$findings = New-Object System.Collections.ArrayList

$ps51Version = [version]$ps51.Version
$ps7Version = [version]$ps7.Version

if ($ps51Version.Major -ne 5 -or $ps51Version.Minor -ne 1 -or $ps51.Edition -ne 'Desktop') {
    Add-Finding -List $findings -Severity BLOCKER -Category 'Audit target' -Item 'Windows PowerShell' `
        -Message 'The baseline executable is not Windows PowerShell 5.1 Desktop.' `
        -Evidence51 ("Version {0}, edition {1}" -f $ps51.Version, $ps51.Edition) `
        -Recommendation 'Point -WindowsPowerShellPath to Windows PowerShell 5.1 powershell.exe.'
}

if ($ps7.Edition -ne 'Core' -or $ps7Version.Major -ne 7) {
    Add-Finding -List $findings -Severity BLOCKER -Category 'Audit target' -Item 'PowerShell 7' `
        -Message 'The target executable is not PowerShell 7 Core.' `
        -Evidence76 ("Version {0}, edition {1}" -f $ps7.Version, $ps7.Edition) `
        -Recommendation 'Point -PowerShell7Path to the intended pwsh.exe.'
}

if ($ps7Version -ne $TargetPowerShellVersion) {
    $versionMismatchSeverity = $(if ($AllowTargetVersionMismatch) { 'WARNING' } else { 'BLOCKER' })
    Add-Finding -List $findings -Severity $versionMismatchSeverity -Category 'Audit target' -Item 'Target version' `
        -Message ("The installed target is {0}, not the requested exact version {1}." -f $ps7Version, $TargetPowerShellVersion) `
        -Evidence76 ([string]$ps7Version) `
        -Recommendation 'Install or select the exact target version, then rerun the audit.'
}

if ($ps51.Identity -ne $ps7.Identity -or $ps51.Sid -ne $ps7.Sid) {
    Add-Finding -List $findings -Severity BLOCKER -Category 'Identity' -Item 'Process identity' `
        -Message 'The two shells ran under different Windows identities. User-scoped modules, profiles, credentials and file access cannot be compared reliably.' `
        -Evidence51 ("{0} ({1})" -f $ps51.Identity, $ps51.Sid) `
        -Evidence76 ("{0} ({1})" -f $ps7.Identity, $ps7.Sid) `
        -Recommendation 'Run both probes under the same real job or service identity.'
}

if ([bool]$ps51.Is64BitProcess -ne [bool]$ps7.Is64BitProcess) {
    Add-Finding -List $findings -Severity WARNING -Category 'Architecture' -Item 'Process bitness' `
        -Message 'Process bitness differs. Registry views, COM components, native DLL loading and module availability can change.' `
        -Evidence51 ([string]$ps51.Is64BitProcess) -Evidence76 ([string]$ps7.Is64BitProcess) `
        -Recommendation 'Test using the same bitness as the production launcher.'
}

if ($ps51.LanguageMode -ne $ps7.LanguageMode) {
    Add-Finding -List $findings -Severity BLOCKER -Category 'Language mode' -Item 'LanguageMode' `
        -Message 'PowerShell language mode differs between the baseline and target.' `
        -Evidence51 $ps51.LanguageMode -Evidence76 $ps7.LanguageMode `
        -Recommendation 'Check application control policy and test under the production identity.'
}

if ($ps51.Culture -ne $ps7.Culture -or $ps51.UICulture -ne $ps7.UICulture) {
    Add-Finding -List $findings -Severity WARNING -Category 'Culture' -Item 'Culture settings' `
        -Message 'Culture or UI culture differs. Date, number, CSV and string conversions may produce different results.' `
        -Evidence51 ("{0}/{1}" -f $ps51.Culture, $ps51.UICulture) `
        -Evidence76 ("{0}/{1}" -f $ps7.Culture, $ps7.UICulture) `
        -Recommendation 'Use explicit cultures and invariant formats where output is machine-consumed.'
}

$targetModulePathKeys = @($ps7.ModulePathEntries | ForEach-Object {
    Get-NormalizedPathKey -Path ([string]$_.Path)
})
foreach ($modulePathEntry in @($ps51.ModulePathEntries)) {
    $modulePathKey = Get-NormalizedPathKey -Path ([string]$modulePathEntry.Path)
    if ([bool]$modulePathEntry.Exists -and $targetModulePathKeys -notcontains $modulePathKey) {
        Add-Finding -List $findings -Severity WARNING -Category 'Module search path' `
            -Item $modulePathEntry.Path `
            -Message 'A module directory searched by Windows PowerShell 5.1 is not present in the PowerShell 7 PSModulePath.' `
            -Evidence51 'Present in PSModulePath' -Evidence76 'Absent from PSModulePath' `
            -Recommendation 'Install required modules in a PowerShell 7 module location or add a deliberately validated path for the real execution identity.'
    }
}

foreach ($probeError in @($ps51.ProbeErrors)) {
    Add-Finding -List $findings -Severity WARNING -Category 'Probe coverage' -Item 'Windows PowerShell probe' `
        -Message ([string]$probeError) -Recommendation 'Review the affected inventory area manually.'
}
foreach ($probeError in @($ps7.ProbeErrors)) {
    Add-Finding -List $findings -Severity WARNING -Category 'Probe coverage' -Item 'PowerShell 7 probe' `
        -Message ([string]$probeError) -Recommendation 'Review the affected inventory area manually.'
}

$targetFilesByPath = @{}
foreach ($file in @($ps7.ParsedFiles)) {
    $targetFilesByPath[[string]$file.Path.ToLowerInvariant()] = $file
}
foreach ($sourceFile in @($ps51.ParsedFiles)) {
    $targetFile = $targetFilesByPath[[string]$sourceFile.Path.ToLowerInvariant()]
    foreach ($parseError in @($sourceFile.ParseErrors)) {
        Add-Finding -List $findings -Severity BLOCKER -Category 'Parsing in 5.1' `
            -File $sourceFile.Path -Line ([int]$parseError.Line) -Item $parseError.Text `
            -Message $parseError.Message `
            -Recommendation 'Correct the Windows PowerShell parser error before assessing migration.'
    }
    if ($targetFile) {
        foreach ($parseError in @($targetFile.ParseErrors)) {
            Add-Finding -List $findings -Severity BLOCKER -Category 'Parsing in 7.6.3' `
                -File $targetFile.Path -Line ([int]$parseError.Line) -Item $parseError.Text `
                -Message $parseError.Message `
                -Recommendation 'Replace or rewrite syntax that PowerShell 7 cannot parse.'
        }
    }
    else {
        Add-Finding -List $findings -Severity WARNING -Category 'Dependency discovery' `
            -File $sourceFile.Path -Item 'Parsed file' `
            -Message 'A file parsed in the 5.1 probe was not discovered by the PowerShell 7 probe.' `
            -Recommendation 'Check path construction, environment variables and edition-specific dependency logic.'
    }

    if ($sourceFile.RequiredPSVersion) {
        try {
            $requiredPSVersion = [version]$sourceFile.RequiredPSVersion
            if ($requiredPSVersion -gt $TargetPowerShellVersion) {
                Add-Finding -List $findings -Severity BLOCKER -Category 'Script requirement' `
                    -File $sourceFile.Path -Line 1 -Item '#Requires -Version' `
                    -Message ("The script requires PowerShell {0} or later, which is newer than target {1}." -f $requiredPSVersion, $TargetPowerShellVersion) `
                    -Recommendation 'Use a suitable target PowerShell version or lower the requirement only after removing newer dependencies.'
            }
            if ($requiredPSVersion -gt [version]'5.1') {
                Add-Finding -List $findings -Severity INFO -Category 'Script requirement' `
                    -File $sourceFile.Path -Line 1 -Item '#Requires -Version' `
                    -Message ("The script declares version {0} or later and therefore is not intended to run on Windows PowerShell 5.1." -f $requiredPSVersion) `
                    -Recommendation 'Confirm whether Windows PowerShell 5.1 is truly the working baseline for this file.'
            }
        }
        catch {
            Add-Finding -List $findings -Severity WARNING -Category 'Script requirement' `
                -File $sourceFile.Path -Line 1 -Item '#Requires -Version' `
                -Message ("The declared PowerShell version could not be compared: {0}" -f $sourceFile.RequiredPSVersion) `
                -Recommendation 'Review the version requirement manually.'
        }
    }

    $requiredEditions = @($sourceFile.RequiredPSEditions |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requiredEditions.Count -gt 0 -and $requiredEditions -notcontains 'Core') {
        Add-Finding -List $findings -Severity BLOCKER -Category 'Script requirement' `
            -File $sourceFile.Path -Line 1 -Item '#Requires -PSEdition' `
            -Message ("The script permits edition(s) {0}, not PowerShell Core." -f ($requiredEditions -join ', ')) `
            -Recommendation 'Remove the Desktop-only requirement only after replacing all Desktop-only dependencies.'
    }

    $requiredAssemblies = @($sourceFile.RequiredAssemblies |
        ForEach-Object { [string]$_ } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($requiredAssemblies.Count -gt 0) {
        Add-Finding -List $findings -Severity REVIEW -Category 'Assembly requirement' `
            -File $sourceFile.Path -Line 1 -Item ($requiredAssemblies -join ', ') `
            -Message 'The script requires one or more assemblies. Static parsing does not prove that their target frameworks and dependencies load on modern .NET.' `
            -Recommendation 'Load and exercise the assemblies in an isolated PowerShell 7.6.3 test.'
    }

    if ($sourceFile.RequiredApplicationId) {
        Add-Finding -List $findings -Severity BLOCKER -Category 'Shell requirement' `
            -File $sourceFile.Path -Line 1 -Item $sourceFile.RequiredApplicationId `
            -Message 'The script declares a Windows PowerShell shell/application ID requirement that is not portable to pwsh.' `
            -Recommendation 'Remove the shell-ID dependency or retain this script on Windows PowerShell 5.1.'
    }
}

$targetCommandByKey = @{}
foreach ($command in @($ps7.Commands)) {
    $targetCommandByKey[(Get-CommandKey $command)] = $command
}

$removedCommands = @(
    'Add-Computer', 'Add-PSSnapin', 'Checkpoint-Computer', 'Clear-EventLog',
    'Complete-Transaction', 'Disable-ComputerRestore', 'Enable-ComputerRestore',
    'Export-BinaryMiLog', 'Export-Console', 'Export-Counter', 'Get-ComputerRestorePoint',
    'Get-ControlPanelItem', 'Get-EventLog', 'Get-PSSnapin', 'Get-Transaction',
    'Get-WmiObject', 'Import-Counter', 'Invoke-WmiMethod', 'Limit-EventLog',
    'New-EventLog', 'New-WebServiceProxy', 'Register-WmiEvent', 'Remove-Computer',
    'Remove-EventLog', 'Remove-PSSnapin', 'Remove-WmiObject',
    'Reset-ComputerMachinePassword', 'Restore-Computer', 'Resume-Job',
    'Set-WmiInstance', 'Start-Transaction', 'Suspend-Job', 'Undo-Transaction',
    'Use-Transaction'
)

$encodingSensitiveCommands = @('Add-Content', 'Export-Csv', 'Out-File', 'Set-Content')
$runtimeSensitiveCommands = @('Add-Type', 'Export-Clixml', 'Import-Clixml', 'Invoke-Command',
    'Invoke-Expression', 'Invoke-RestMethod', 'Invoke-WebRequest', 'Start-Job')
$seenGeneralRisks = @{}

foreach ($sourceCommand in @($ps51.Commands)) {
    $commandName = [string]$sourceCommand.Name
    $targetCommand = $targetCommandByKey[(Get-CommandKey $sourceCommand)]

    if ([string]::IsNullOrWhiteSpace($commandName)) {
        Add-Finding -List $findings -Severity REVIEW -Category 'Dynamic command' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $sourceCommand.Text `
            -Message 'The command name is calculated at runtime and cannot be resolved statically.' `
            -Recommendation 'Exercise this path in a controlled PowerShell 7 test using representative data.'
        continue
    }

    if ($commandName -ieq 'Import-Module' -and @($sourceCommand.LiteralArguments).Count -eq 0) {
        Add-Finding -List $findings -Severity REVIEW -Category 'Dynamic module import' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $sourceCommand.Text `
            -Message 'The imported module name or path is calculated at runtime and could not be compared statically.' `
            -Recommendation 'Resolve the final module path and version under both real execution environments.'
    }

    if ($removedCommands -contains $commandName -and
        $sourceCommand.ResolutionKind -ne 'LocalScript' -and
        ($null -eq $targetCommand -or -not [bool]$targetCommand.Found)) {
        Add-Finding -List $findings -Severity BLOCKER -Category 'Removed command' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $commandName `
            -Message ("{0} is a Windows PowerShell command removed from PowerShell 7." -f $commandName) `
            -Evidence51 ("{0} {1}" -f $sourceCommand.Source, $sourceCommand.Version) `
            -Evidence76 'Removed from PowerShell 7' `
            -Recommendation 'Replace it with the supported PowerShell 7 equivalent or retain this path on Windows PowerShell 5.1.'
    }
    elseif ([bool]$sourceCommand.Found -and ($null -eq $targetCommand -or -not [bool]$targetCommand.Found)) {
        Add-Finding -List $findings -Severity BLOCKER -Category 'Command availability' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $commandName `
            -Message 'The command resolves in the 5.1 environment but not in the PowerShell 7 environment.' `
            -Evidence51 ("{0} {1} ({2})" -f $sourceCommand.Source, $sourceCommand.Version, $sourceCommand.ResolutionKind) `
            -Evidence76 'Not found' `
            -Recommendation 'Install a PowerShell 7-compatible module, use Windows PowerShell compatibility where suitable or retain the script on 5.1.'
    }
    elseif (-not [bool]$sourceCommand.Found -and ($null -eq $targetCommand -or -not [bool]$targetCommand.Found)) {
        Add-Finding -List $findings -Severity REVIEW -Category 'Unresolved command' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $commandName `
            -Message 'The command did not resolve in either clean probe. It may be defined dynamically, imported conditionally or supplied by the production host.' `
            -Recommendation 'Identify where the command is defined and verify that dependency explicitly in PowerShell 7.'
    }
    elseif ($targetCommand -and -not [bool]$targetCommand.EditionCompatible) {
        Add-Finding -List $findings -Severity BLOCKER -Category 'Module edition' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $commandName `
            -Message 'The target command was indexed from a module whose manifest does not list the Core edition.' `
            -Evidence76 ("{0} {1}" -f $targetCommand.Source, $targetCommand.Version) `
            -Recommendation 'Obtain a Core-compatible module or test Import-Module -UseWindowsPowerShell on Windows.'
    }
    elseif ($targetCommand -and $sourceCommand.Source -and $targetCommand.Source -and
        $sourceCommand.Source -ne $targetCommand.Source) {
        Add-Finding -List $findings -Severity WARNING -Category 'Command resolution' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $commandName `
            -Message 'The command resolves from different sources in the two environments.' `
            -Evidence51 ("{0} {1}" -f $sourceCommand.Source, $sourceCommand.Version) `
            -Evidence76 ("{0} {1}" -f $targetCommand.Source, $targetCommand.Version) `
            -Recommendation 'Confirm that the PowerShell 7 implementation has compatible behaviour and output types.'
    }

    if ($targetCommand -and $targetCommand.ResolutionKind -eq 'AvailableModule') {
        $moduleMetadataRiskKey = 'ModuleMetadata|{0}|{1}' -f $targetCommand.Source, $targetCommand.Version
        if (-not $seenGeneralRisks.ContainsKey($moduleMetadataRiskKey)) {
            $seenGeneralRisks[$moduleMetadataRiskKey] = $true
            Add-Finding -List $findings -Severity REVIEW -Category 'Module load validation' `
                -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $targetCommand.Source `
                -Message 'The target module advertises this command, but the auditor did not import the module because module initialisation code can have side effects.' `
                -Evidence76 ("{0} {1}" -f $targetCommand.Source, $targetCommand.Version) `
                -Recommendation 'Import the module in an isolated PowerShell 7.6.3 process and test the command with representative inputs.'
        }
    }

    if ($targetCommand -and @($sourceCommand.AvailableParameters).Count -gt 0 -and
        @($targetCommand.AvailableParameters).Count -gt 0) {
        foreach ($usedParameter in @($sourceCommand.ParametersUsed)) {
            if ($sourceCommand.AvailableParameters -contains $usedParameter -and
                $targetCommand.AvailableParameters -notcontains $usedParameter) {
                Add-Finding -List $findings -Severity BLOCKER -Category 'Command parameter' `
                    -File $sourceCommand.File -Line ([int]$sourceCommand.Line) `
                    -Item ("{0} -{1}" -f $commandName, $usedParameter) `
                    -Message 'A named parameter accepted by the 5.1 command is not present on the resolved PowerShell 7 command.' `
                    -Evidence51 ("{0} {1}" -f $sourceCommand.Source, $sourceCommand.Version) `
                    -Evidence76 ("{0} {1}" -f $targetCommand.Source, $targetCommand.Version) `
                    -Recommendation 'Update the call for the target command syntax and retest the affected path.'
            }
        }
    }

    if ($encodingSensitiveCommands -contains $commandName -and
        $sourceCommand.ParametersUsed -notcontains 'Encoding') {
        Add-Finding -List $findings -Severity WARNING -Category 'Default encoding' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $commandName `
            -Message 'No explicit encoding is specified and default text encodings differ between Windows PowerShell 5.1 and PowerShell 7.' `
            -Recommendation 'Specify the required encoding explicitly and verify the consumer of the file.'
    }

    if ($runtimeSensitiveCommands -contains $commandName) {
        $riskKey = '{0}|{1}|{2}' -f $sourceCommand.File, $sourceCommand.Line, $commandName
        if (-not $seenGeneralRisks.ContainsKey($riskKey)) {
            $seenGeneralRisks[$riskKey] = $true
            Add-Finding -List $findings -Severity REVIEW -Category 'Runtime-sensitive operation' `
                -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $commandName `
                -Message 'This operation depends on runtime state, external endpoints, serialization or target-framework behaviour that static analysis cannot prove.' `
                -Recommendation 'Test this operation with the production identity, representative inputs and non-production dependencies.'
        }
    }

    if ($sourceCommand.CommandType -eq 'Application' -or
        ($targetCommand -and $targetCommand.CommandType -eq 'Application')) {
        Add-Finding -List $findings -Severity REVIEW -Category 'Native command' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $commandName `
            -Message 'Native executable argument passing, quoting, encoding and exit-code handling can differ in PowerShell 7.' `
            -Recommendation 'Test exact arguments, standard streams and nonzero exit codes under PowerShell 7.6.3.'
    }

    if ($commandName -in @('powershell', 'powershell.exe')) {
        Add-Finding -List $findings -Severity WARNING -Category 'Nested shell' `
            -File $sourceCommand.File -Line ([int]$sourceCommand.Line) -Item $commandName `
            -Message 'The script explicitly starts Windows PowerShell, so part of the workload will remain on 5.1 after the launcher moves to pwsh.' `
            -Recommendation 'Decide whether this is an intentional compatibility boundary or should call pwsh explicitly.'
    }
}

$riskyTypePatterns = [ordered]@{
    '^System\.Web(\.|$)'                         = 'System.Web and full .NET Framework dependencies may not be available or may behave differently on modern .NET.'
    '^System\.Workflow(\.|$)'                    = 'Windows Workflow Foundation and PowerShell Workflow are not supported by PowerShell 7.'
    '^System\.Runtime\.Remoting(\.|$)'          = '.NET Remoting APIs are not supported on modern .NET.'
    '^System\.Management\.Automation\.PSSnapIn' = 'PowerShell snap-ins are not supported by PowerShell 7.'
    '^WMI(CLASS)?$'                               = 'The WMI type accelerators are Windows PowerShell-era dependencies and require replacement or direct target validation.'
    '^System\.Net\.ServicePointManager$'         = 'ServicePointManager settings do not control all HTTP behaviour in PowerShell 7, which uses modern .NET HTTP handlers.'
    '^System\.Runtime\.Serialization\.Formatters\.Binary\.BinaryFormatter$' = 'BinaryFormatter is obsolete and restricted or disabled in modern .NET.'
}

foreach ($typeReference in @($ps51.TypeReferences)) {
    foreach ($pattern in $riskyTypePatterns.Keys) {
        if ([string]$typeReference.Name -match $pattern) {
            Add-Finding -List $findings -Severity WARNING -Category '.NET or type compatibility' `
                -File $typeReference.File -Line ([int]$typeReference.Line) -Item $typeReference.Text `
                -Message $riskyTypePatterns[$pattern] `
                -Recommendation 'Replace the dependency where possible and run a focused PowerShell 7 test.'
            break
        }
    }
}

$profileKinds = @('AllUsersAllHosts', 'AllUsersCurrentHost', 'CurrentUserAllHosts', 'CurrentUserCurrentHost')
foreach ($kind in $profileKinds) {
    $sourceProfile = @($ps51.Profiles | Where-Object { $_.Kind -eq $kind } | Select-Object -First 1)
    $targetProfile = @($ps7.Profiles | Where-Object { $_.Kind -eq $kind } | Select-Object -First 1)
    if ($sourceProfile.Count -gt 0 -and [bool]$sourceProfile[0].Exists -and
        ($targetProfile.Count -eq 0 -or -not [bool]$targetProfile[0].Exists)) {
        $imports = ConvertTo-DisplayText $sourceProfile[0].StaticModuleImports
        Add-Finding -List $findings -Severity WARNING -Category 'Profile separation' -Item $kind `
            -Message ("The 5.1 profile exists but the corresponding PowerShell 7 profile does not. Static module imports: {0}" -f $imports) `
            -Evidence51 $sourceProfile[0].Path `
            -Evidence76 $(if ($targetProfile.Count -gt 0) { $targetProfile[0].Path } else { 'No profile path returned' }) `
            -Recommendation 'Move only the required, PowerShell 7-compatible setup into the separate PowerShell 7 profile or make the script import its own dependencies.'
    }
    elseif ($sourceProfile.Count -gt 0 -and $targetProfile.Count -gt 0 -and
        [bool]$sourceProfile[0].Exists -and [bool]$targetProfile[0].Exists -and
        $sourceProfile[0].Sha256 -ne $targetProfile[0].Sha256) {
        Add-Finding -List $findings -Severity INFO -Category 'Profile separation' -Item $kind `
            -Message 'The 5.1 and PowerShell 7 profiles are different files with different contents.' `
            -Evidence51 $sourceProfile[0].Path -Evidence76 $targetProfile[0].Path `
            -Recommendation 'Confirm that any required module imports and environment setup exist in the correct profile.'
    }


    if ($sourceProfile.Count -gt 0 -and $targetProfile.Count -gt 0 -and
        [bool]$sourceProfile[0].Exists -and [bool]$targetProfile[0].Exists) {
        $targetProfileImports = @($targetProfile[0].StaticModuleImports | ForEach-Object { [string]$_ })
        foreach ($profileImport in @($sourceProfile[0].StaticModuleImports)) {
            if ($targetProfileImports -notcontains [string]$profileImport) {
                Add-Finding -List $findings -Severity WARNING -Category 'Profile module import' -Item $profileImport `
                    -Message ("The {0} profile imports this module in Windows PowerShell but not in PowerShell 7." -f $kind) `
                    -Evidence51 $sourceProfile[0].Path -Evidence76 $targetProfile[0].Path `
                    -Recommendation 'Make the supplied script import its required modules explicitly, or configure the separate PowerShell 7 profile after compatibility testing.'
            }
        }
    }
}

if ($IncludeProfileSessions) {
    $ps51Loaded = @($ps51Profile.LoadedModules | ForEach-Object { $_.Name } | Sort-Object -Unique)
    $ps7Loaded = @($ps7Profile.LoadedModules | ForEach-Object { $_.Name } | Sort-Object -Unique)
    foreach ($moduleName in $ps51Loaded) {
        if ($ps7Loaded -notcontains $moduleName) {
            Add-Finding -List $findings -Severity WARNING -Category 'Profile-loaded module' -Item $moduleName `
                -Message 'This module is loaded after the Windows PowerShell profile runs but not after the PowerShell 7 profile runs.' `
                -Recommendation 'Import the dependency in the script or configure the separate PowerShell 7 profile after confirming compatibility.'
        }
    }
}

$moduleReferences = @($ps51.ModuleReferences | Sort-Object Name, File, Line -Unique)
foreach ($reference in $moduleReferences) {
    if ($reference.ResolvedPath) {
        continue
    }
    $sourceModules = @($ps51.AvailableModules | Where-Object { $_.Name -ieq [string]$reference.Name })
    $targetModules = @($ps7.AvailableModules | Where-Object { $_.Name -ieq [string]$reference.Name })
    $targetCompatibleModules = @($targetModules | Where-Object { [bool]$_.EditionCompatible })
    $sourceModule = Get-HighestModule -Modules $sourceModules -Name ([string]$reference.Name)
    $targetModule = Get-HighestModule -Modules $targetCompatibleModules -Name ([string]$reference.Name)
    if (-not $targetModule) {
        $targetModule = Get-HighestModule -Modules $targetModules -Name ([string]$reference.Name)
    }
    if ($sourceModule -and -not $targetModule) {
        Add-Finding -List $findings -Severity BLOCKER -Category 'Module availability' `
            -File $reference.File -Line ([int]$reference.Line) -Item $reference.Name `
            -Message 'A referenced module is available to Windows PowerShell 5.1 but absent from the PowerShell 7 module inventory.' `
            -Evidence51 ("{0} at {1}" -f $sourceModule.Version, $sourceModule.Path) `
            -Evidence76 'Not found' `
            -Recommendation 'Install a Core-compatible version for the real execution identity or assess -UseWindowsPowerShell.'
    }
    elseif ($targetModules.Count -gt 0 -and $targetCompatibleModules.Count -eq 0) {
        Add-Finding -List $findings -Severity BLOCKER -Category 'Module edition' `
            -File $reference.File -Line ([int]$reference.Line) -Item $reference.Name `
            -Message 'The referenced target module explicitly excludes the Core edition.' `
            -Evidence76 ("{0}; CompatiblePSEditions={1}" -f $targetModule.Path, (ConvertTo-DisplayText $targetModule.CompatiblePSEditions)) `
            -Recommendation 'Use a Core-compatible module version or assess Windows PowerShell compatibility remoting.'
    }
    elseif (-not $sourceModule -and -not $targetModule) {
        Add-Finding -List $findings -Severity REVIEW -Category 'Module availability' `
            -File $reference.File -Line ([int]$reference.Line) -Item $reference.Name `
            -Message 'A statically referenced module was not found in either clean environment inventory.' `
            -Recommendation 'Verify the module name or path under the production identity.'
    }

    $matchingTargetModules = @($targetCompatibleModules)
    if ($reference.Guid) {
        $matchingTargetModules = @($matchingTargetModules | Where-Object { $_.Guid -ieq [string]$reference.Guid })
    }
    if ($reference.RequiredVersion) {
        $matchingTargetModules = @($matchingTargetModules | Where-Object {
            [version]$_.Version -eq [version]$reference.RequiredVersion
        })
    }
    else {
        if ($reference.MinimumVersion) {
            $matchingTargetModules = @($matchingTargetModules | Where-Object {
                [version]$_.Version -ge [version]$reference.MinimumVersion
            })
        }
        if ($reference.MaximumVersion) {
            $matchingTargetModules = @($matchingTargetModules | Where-Object {
                [version]$_.Version -le [version]$reference.MaximumVersion
            })
        }
    }

    $hasModuleConstraint = $reference.Guid -or $reference.RequiredVersion -or
        $reference.MinimumVersion -or $reference.MaximumVersion
    if ($targetModules.Count -gt 0 -and $hasModuleConstraint -and $matchingTargetModules.Count -eq 0) {
        $constraintText = @(
            $(if ($reference.Guid) { 'Guid=' + $reference.Guid })
            $(if ($reference.RequiredVersion) { 'RequiredVersion=' + $reference.RequiredVersion })
            $(if ($reference.MinimumVersion) { 'MinimumVersion=' + $reference.MinimumVersion })
            $(if ($reference.MaximumVersion) { 'MaximumVersion=' + $reference.MaximumVersion })
        ) -join '; '
        Add-Finding -List $findings -Severity BLOCKER -Category 'Module version' `
            -File $reference.File -Line ([int]$reference.Line) -Item $reference.Name `
            -Message 'No Core-compatible target module satisfies the declared module identity or version constraint.' `
            -Evidence76 ("Constraint: {0}; installed versions: {1}" -f $constraintText, (($targetModules.Version | Sort-Object -Unique) -join ', ')) `
            -Recommendation 'Install the required Core-compatible module version for the real execution identity.'
    }

    if ($targetModule -and @($targetModule.CompatiblePSEditions | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    }).Count -eq 0) {
        Add-Finding -List $findings -Severity REVIEW -Category 'Module compatibility declaration' `
            -File $reference.File -Line ([int]$reference.Line) -Item $reference.Name `
            -Message 'The module manifest does not explicitly declare CompatiblePSEditions, so discovery alone does not prove that it runs on PowerShell Core.' `
            -Evidence76 ("{0} {1}" -f $targetModule.Path, $targetModule.Version) `
            -Recommendation 'Import and exercise the module in an isolated PowerShell 7.6.3 process.'
    }
}

$ps51ModuleNames = @($ps51.AvailableModules | ForEach-Object { $_.Name } | Sort-Object -Unique)
$ps7ModuleNames = @($ps7.AvailableModules | ForEach-Object { $_.Name } | Sort-Object -Unique)
$onlyIn51 = @($ps51ModuleNames | Where-Object { $ps7ModuleNames -notcontains $_ })
$onlyIn7 = @($ps7ModuleNames | Where-Object { $ps51ModuleNames -notcontains $_ })

if ($onlyIn51.Count -gt 0) {
    Add-Finding -List $findings -Severity INFO -Category 'Environment module inventory' `
        -Item ("{0} module name(s) only in 5.1" -f $onlyIn51.Count) `
        -Message ("Full list is in module-comparison.csv. Names: {0}" -f (($onlyIn51 | Select-Object -First 20) -join ', ')) `
        -Recommendation 'Treat these as relevant only if the script or its runtime paths depend on them.'
}

Add-Finding -List $findings -Severity REVIEW -Category 'Runtime coverage' -Item 'Controlled execution' `
    -Message 'Static analysis cannot exercise data-dependent branches, external systems, permissions, credentials, remoting endpoints or code generated at runtime.' `
    -Recommendation 'Complete migration sign-off with a non-production PowerShell 7.6.3 run under the real execution identity and representative inputs.'

$findings = @($findings | Sort-Object @{ Expression = {
    switch ($_.Severity) { 'BLOCKER' { 0 } 'WARNING' { 1 } 'REVIEW' { 2 } default { 3 } }
}}, Category, File, Line, Item)

$blockerCount = @($findings | Where-Object { $_.Severity -eq 'BLOCKER' }).Count
$warningCount = @($findings | Where-Object { $_.Severity -eq 'WARNING' }).Count
$reviewCount = @($findings | Where-Object { $_.Severity -eq 'REVIEW' }).Count
$infoCount = @($findings | Where-Object { $_.Severity -eq 'INFO' }).Count

$conclusion = if ($blockerCount -gt 0) {
    'The supplied script is **not cleared for PowerShell {0}**. Resolve the blocking findings, then repeat the audit and controlled runtime testing.' -f $TargetPowerShellVersion
}
else {
    'No statically confirmed blocker was found. This is **not a guarantee of runtime compatibility**; complete the listed manual checks and a controlled PowerShell {0} test.' -f $TargetPowerShellVersion
}

$moduleComparison = @()
$allModuleNames = @($ps51ModuleNames + $ps7ModuleNames | Sort-Object -Unique)
foreach ($moduleName in $allModuleNames) {
    $sourceModule = Get-HighestModule -Modules @($ps51.AvailableModules) -Name $moduleName
    $targetModule = Get-HighestModule -Modules @($ps7.AvailableModules) -Name $moduleName
    $moduleComparison += [pscustomobject][ordered]@{
        Name                    = $moduleName
        PS51HighestVersion      = $(if ($sourceModule) { $sourceModule.Version } else { '' })
        PS51Path                = $(if ($sourceModule) { $sourceModule.Path } else { '' })
        PS7HighestVersion       = $(if ($targetModule) { $targetModule.Version } else { '' })
        PS7Path                 = $(if ($targetModule) { $targetModule.Path } else { '' })
        PS7CompatiblePSEditions = $(if ($targetModule) { ConvertTo-DisplayText $targetModule.CompatiblePSEditions } else { '' })
        OnlyIn                 = $(
            if ($sourceModule -and -not $targetModule) { 'Windows PowerShell 5.1' }
            elseif ($targetModule -and -not $sourceModule) { 'PowerShell 7' }
            else { '' }
        )
    }
}

$report = [pscustomobject][ordered]@{
    SchemaVersion          = '1.0'
    GeneratedAt            = (Get-Date).ToString('o')
    ScriptPath             = $resolvedScriptPath
    RequestedTargetVersion = [string]$TargetPowerShellVersion
    IncludeProfileSessions = [bool]$IncludeProfileSessions
    Summary                = [pscustomobject][ordered]@{
        Blockers    = $blockerCount
        Warnings    = $warningCount
        Review      = $reviewCount
        Information = $infoCount
        Conclusion  = $conclusion
    }
    WindowsPowerShell      = [pscustomobject][ordered]@{
        Version                  = $ps51.Version
        Edition                  = $ps51.Edition
        Executable               = $ps51.Executable
        Identity                 = $ps51.Identity
        Sid                      = $ps51.Sid
        Bitness                  = $(if ([bool]$ps51.Is64BitProcess) { '64-bit' } else { '32-bit' })
        LanguageMode             = $ps51.LanguageMode
        Culture                  = ("{0}/{1}" -f $ps51.Culture, $ps51.UICulture)
        PSHome                   = $ps51.PSHome
        ModulePathEntries        = @($ps51.ModulePathEntries)
        Profiles                 = @($ps51.Profiles)
        ExecutionPolicies        = @($ps51.ExecutionPolicies)
        AvailableModuleNameCount = $ps51ModuleNames.Count
    }
    PowerShell7            = [pscustomobject][ordered]@{
        Version                  = $ps7.Version
        Edition                  = $ps7.Edition
        Executable               = $ps7.Executable
        Identity                 = $ps7.Identity
        Sid                      = $ps7.Sid
        Bitness                  = $(if ([bool]$ps7.Is64BitProcess) { '64-bit' } else { '32-bit' })
        LanguageMode             = $ps7.LanguageMode
        Culture                  = ("{0}/{1}" -f $ps7.Culture, $ps7.UICulture)
        PSHome                   = $ps7.PSHome
        ModulePathEntries        = @($ps7.ModulePathEntries)
        Profiles                 = @($ps7.Profiles)
        ExecutionPolicies        = @($ps7.ExecutionPolicies)
        AvailableModuleNameCount = $ps7ModuleNames.Count
    }
    ParsedFiles             = @($ps51.ParsedFiles)
    Findings                = @($findings)
    ModuleComparison        = @($moduleComparison)
    RawEvidence             = [pscustomobject][ordered]@{
        WindowsPowerShellClean = $ps51
        PowerShell7Clean       = $ps7
        WindowsPowerShellProfile = $ps51Profile
        PowerShell7Profile       = $ps7Profile
    }
}

$markdownPath = Join-Path $OutputDirectory 'compatibility-report.md'
$jsonPath = Join-Path $OutputDirectory 'compatibility-audit.json'
$findingsCsvPath = Join-Path $OutputDirectory 'compatibility-findings.csv'
$modulesCsvPath = Join-Path $OutputDirectory 'module-comparison.csv'

$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$findings | Export-Csv -LiteralPath $findingsCsvPath -NoTypeInformation -Encoding UTF8
$moduleComparison | Export-Csv -LiteralPath $modulesCsvPath -NoTypeInformation -Encoding UTF8
Write-MarkdownReport -Path $markdownPath -Report $report

Remove-Item -LiteralPath $ps51ResultPath, $ps7ResultPath, $ps51ProfileResultPath, $ps7ProfileResultPath `
    -Force -ErrorAction SilentlyContinue

Write-Output ("Compatibility audit complete: {0}" -f $markdownPath)
Write-Output ("Blocking findings: {0}; warnings: {1}; manual review: {2}; information: {3}" -f
    $blockerCount, $warningCount, $reviewCount, $infoCount)

if ($blockerCount -gt 0) {
    exit 1
}
exit 0
