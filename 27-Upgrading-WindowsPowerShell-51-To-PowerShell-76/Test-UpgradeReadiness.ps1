<#
.SYNOPSIS
    Scans a Windows PowerShell 5.1 code directory for PowerShell 7.6+ upgrade work.
.DESCRIPTION
    Reads PowerShell files under a target directory and reports patterns that need review before moving to PowerShell
    7.6+. Optional wrapper-file scanning can include launch scripts and configuration files. The script is read-only.
.EXAMPLE
    ./Test-UpgradeReadiness.ps1 -Path ./LegacyScripts
.EXAMPLE
    ./Test-UpgradeReadiness.ps1 -Path ./LegacyScripts -IncludeWrapperFiles -Format Json
.EXAMPLE
    ./Test-UpgradeReadiness.ps1 -Path ./LegacyScripts -Format Json -OutputPath ./upgrade-readiness.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $Path,

    [ValidateSet('Table', 'Json')]
    [string] $Format = 'Table',

    [switch] $IncludeWrapperFiles,

    [string] $OutputPath
)

function New-UpgradeFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $File,

        [Parameter(Mandatory = $true)]
        [int] $Line,

        [Parameter(Mandatory = $true)]
        [string] $Pattern,

        [Parameter(Mandatory = $true)]
        [string] $Decision,

        [Parameter(Mandatory = $true)]
        [string] $Action,

        [Parameter(Mandatory = $true)]
        [string] $Evidence
    )

    [pscustomobject]@{
        File = $File
        Line = $Line
        Pattern = $Pattern
        Decision = $Decision
        Action = $Action
        Evidence = $Evidence.Trim()
    }
}

function Get-UpgradeScanFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $RootPath,

        [switch] $IncludeWrappers
    )

    if (-not (Test-Path -Path $RootPath -PathType Container)) {
        Write-Error -Message "Directory was not found: $RootPath" -ErrorAction Stop
    }

    $PowerShellExtensions = @('.ps1', '.psm1', '.psd1')
    $WrapperExtensions = @('.bat', '.cmd', '.xml', '.yml', '.yaml', '.config', '.run')
    $AllowedExtensions = if ($IncludeWrappers.IsPresent) {
        $PowerShellExtensions + $WrapperExtensions
    } else {
        $PowerShellExtensions
    }

    Get-ChildItem -Path $RootPath -Recurse -File |
        Where-Object {
            $_.FullName -ne $PSCommandPath -and $_.Extension.ToLowerInvariant() -in $AllowedExtensions
        }
}

function Test-CommandHasParameter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst] $Command,

        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    [bool] (
        $Command.CommandElements |
            Where-Object {
                $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                $_.ParameterName -eq $Name
            } |
            Select-Object -First 1
    )
}

function Test-CommandHasArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst] $Command,

        [Parameter(Mandatory = $true)]
        [string] $Pattern
    )

    [bool] (
        $Command.CommandElements |
            Select-Object -Skip 1 |
            Where-Object { $_.Extent.Text -match $Pattern } |
            Select-Object -First 1
    )
}

function New-CommandFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst] $Command,

        [Parameter(Mandatory = $true)]
        [string] $File,

        [Parameter(Mandatory = $true)]
        [string] $Pattern,

        [Parameter(Mandatory = $true)]
        [string] $Decision,

        [Parameter(Mandatory = $true)]
        [string] $Action
    )

    $Params = @{
        File = $File
        Line = $Command.Extent.StartLineNumber
        Pattern = $Pattern
        Decision = $Decision
        Action = $Action
        Evidence = $Command.Extent.Text
    }
    New-UpgradeFinding @Params
}

function Test-UpgradeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.CommandAst] $Command,

        [Parameter(Mandatory = $true)]
        [string] $File
    )

    $CommandName = $Command.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        $CommandName = $Command.CommandElements[0].Extent.Text
    }

    $NormalizedName = $CommandName.Trim('"', "'").ToLowerInvariant()

    if ($NormalizedName -in @('powershell', 'powershell.exe')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'Runtime executable' -Decision 'UpdateRequired' `
            -Action 'Review wrapper or scheduled job command and use pwsh when PowerShell 7.6+ is required.'
    }

    if ($NormalizedName -eq 'write-host') {
        New-CommandFinding -Command $Command -File $File -Pattern 'Host-only output' -Decision 'UpdateRequired' `
            -Action 'Use Write-Information, Write-Verbose or structured output objects.'
    }

    if ($NormalizedName -eq 'import-module' -and
        (Test-CommandHasArgument -Command $Command -Pattern '\bActiveDirectory\b')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'Active Directory module' -Decision 'WindowsOnly' `
            -Action 'Validate on Windows and consider Import-Module -UseWindowsPowerShell from PowerShell 7.'
    }

    if ($NormalizedName -match '^(get|set|new|remove|add)-ad(user|group|computer|object)?$') {
        New-CommandFinding -Command $Command -File $File -Pattern 'Active Directory command' -Decision 'WindowsOnly' `
            -Action 'Validate Active Directory commands on a prepared Windows host.'
    }

    if ($NormalizedName -eq 'invoke-command' -and
        -not (Test-CommandHasParameter -Command $Command -Name 'ConfigurationName')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'Remoting endpoint' `
            -Decision 'LiveValidationRequired' `
            -Action 'Confirm whether the target host needs a PowerShell.7 endpoint and test remoting separately.'
    }

    if ($NormalizedName -eq 'convertto-json' -and
        -not (Test-CommandHasParameter -Command $Command -Name 'Depth')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'JSON depth' -Decision 'UpdateRequired' `
            -Action 'Add an explicit ConvertTo-Json -Depth value for nested output.'
    }

    if ($NormalizedName -in @('export-csv', 'set-content', 'out-file') -and
        -not (Test-CommandHasParameter -Command $Command -Name 'Encoding')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'File encoding' -Decision 'UpdateRequired' `
            -Action 'Set encoding explicitly for files shared outside the script.'
    }

    if ($NormalizedName -in @('invoke-webrequest', 'invoke-restmethod')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'Web cmdlet behavior' `
            -Decision 'LiveValidationRequired' `
            -Action 'Review authentication, retry, content type and response parsing behavior in PowerShell 7.'
    }

    if ($NormalizedName -in @('get-wmiobject', 'invoke-wmimethod', 'set-wmiinstance', 'remove-wmiobject')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'WMI cmdlet' -Decision 'WindowsOnly' `
            -Action 'Replace with CIM cmdlets where possible or document the script as Windows-only.'
    }

    if ($NormalizedName -eq 'new-object' -and
        (Test-CommandHasParameter -Command $Command -Name 'ComObject')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'COM object' -Decision 'WindowsOnly' `
            -Action 'Validate COM automation on Windows or replace with a cross-platform API.'
    }

    if ($NormalizedName -eq 'start-process' -and
        (Test-CommandHasParameter -Command $Command -Name 'Credential')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'Credential launch' -Decision 'WindowsOnly' `
            -Action 'Validate credential launch behavior on a prepared Windows host.'
    }

    if ($NormalizedName -in @('register-scheduledjob', 'get-scheduledjob', 'new-jobtrigger')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'Scheduled job cmdlet' -Decision 'WindowsOnly' `
            -Action 'Review PSScheduledJob usage because compatibility mode blocks that module by default.'
    }

    if ($NormalizedName -in @('git', 'robocopy', 'xcopy', 'icacls', 'net', 'cmd', 'schtasks', 'reg', 'msiexec')) {
        New-CommandFinding -Command $Command -File $File -Pattern 'Native command boundary' `
            -Decision 'LiveValidationRequired' `
            -Action 'Confirm native command exit handling, captured output and quoting in PowerShell 7.'
    }
}

function Test-UpgradeTypeExpression {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.TypeExpressionAst] $TypeExpression,

        [Parameter(Mandatory = $true)]
        [string] $File
    )

    $TypeName = $TypeExpression.TypeName.FullName
    if ($TypeName -match '^(System\.Web|System\.DirectoryServices|Microsoft\.VisualBasic)') {
        $Params = @{
            File = $File
            Line = $TypeExpression.Extent.StartLineNumber
            Pattern = '.NET Framework API'
            Decision = 'LiveValidationRequired'
            Action = 'Review direct .NET Framework API usage against the PowerShell 7 runtime.'
            Evidence = $TypeExpression.Extent.Text
        }
        New-UpgradeFinding @Params
    }

    if ($TypeName -in @('adsi', 'adsisearcher', 'wmiclass')) {
        $Params = @{
            File = $File
            Line = $TypeExpression.Extent.StartLineNumber
            Pattern = 'Windows type accelerator'
            Decision = 'WindowsOnly'
            Action = 'Validate ADSI or WMI type accelerator usage on Windows.'
            Evidence = $TypeExpression.Extent.Text
        }
        New-UpgradeFinding @Params
    }
}

function Test-UpgradeVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.VariableExpressionAst] $Variable,

        [Parameter(Mandatory = $true)]
        [string] $File
    )

    if ($Variable.VariablePath.UserPath -in @('PROFILE', 'PSModulePath', 'OutputEncoding')) {
        $Params = @{
            File = $File
            Line = $Variable.Extent.StartLineNumber
            Pattern = 'Session environment boundary'
            Decision = 'UpdateRequired'
            Action = 'Review profile, module path or encoding assumptions for side-by-side PowerShell versions.'
            Evidence = $Variable.Extent.Text
        }
        New-UpgradeFinding @Params
    }
}

function Test-UpgradeToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.Token[]] $Token,

        [Parameter(Mandatory = $true)]
        [string] $File
    )

    foreach ($Item in $Token) {
        if ($Item.Text -match '\[Net\.ServicePointManager\]::SecurityProtocol') {
            $Params = @{
                File = $File
                Line = $Item.Extent.StartLineNumber
                Pattern = 'TLS override'
                Decision = 'UpdateRequired'
                Action = 'Review whether explicit TLS framework settings are still needed in PowerShell 7.'
                Evidence = $Item.Text
            }
            New-UpgradeFinding @Params
        }

        if ($Item.Text -match '\$PSScriptRoot\\|\$PWD\\|[A-Z]:\\') {
            $Params = @{
                File = $File
                Line = $Item.Extent.StartLineNumber
                Pattern = 'Windows path assumption'
                Decision = 'UpdateRequired'
                Action = 'Use Join-Path or document the script as Windows-only.'
                Evidence = $Item.Text
            }
            New-UpgradeFinding @Params
        }
    }
}

function Test-UpgradeManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File
    )

    if ($File.Extension -ne '.psd1') {
        return
    }

    try {
        $Data = Import-PowerShellDataFile -Path $File.FullName -ErrorAction Stop
    } catch {
        return
    }

    if (-not $Data.ContainsKey('CompatiblePSEditions')) {
        $Params = @{
            File = $File.FullName
            Line = 1
            Pattern = 'Module manifest edition'
            Decision = 'UpdateRequired'
            Action = 'Add CompatiblePSEditions after validating whether the module supports Core.'
            Evidence = 'CompatiblePSEditions is not present.'
        }
        New-UpgradeFinding @Params
    } elseif ('Core' -notin @($Data.CompatiblePSEditions)) {
        $Params = @{
            File = $File.FullName
            Line = 1
            Pattern = 'Module manifest edition'
            Decision = 'WindowsOnly'
            Action = 'Manifest does not declare Core compatibility.'
            Evidence = "CompatiblePSEditions: $($Data.CompatiblePSEditions -join ', ')"
        }
        New-UpgradeFinding @Params
    }
}

function Test-PowerShellUpgradeFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File
    )

    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref] $Tokens, [ref] $Errors)

    foreach ($ErrorRecord in $Errors) {
        $Params = @{
            File = $File.FullName
            Line = $ErrorRecord.Extent.StartLineNumber
            Pattern = 'Parser error'
            Decision = 'UpdateRequired'
            Action = 'Fix parser error before testing in PowerShell 7.6+.'
            Evidence = $ErrorRecord.Message
        }
        New-UpgradeFinding @Params
    }

    $Commands = $Ast.FindAll({
        param($Node)
        $Node -is [System.Management.Automation.Language.CommandAst]
    }, $true)
    foreach ($Command in $Commands) {
        Test-UpgradeCommand -Command $Command -File $File.FullName
    }

    $TypeExpressions = $Ast.FindAll({
        param($Node)
        $Node -is [System.Management.Automation.Language.TypeExpressionAst]
    }, $true)
    foreach ($TypeExpression in $TypeExpressions) {
        Test-UpgradeTypeExpression -TypeExpression $TypeExpression -File $File.FullName
    }

    $Variables = $Ast.FindAll({
        param($Node)
        $Node -is [System.Management.Automation.Language.VariableExpressionAst]
    }, $true)
    foreach ($Variable in $Variables) {
        Test-UpgradeVariable -Variable $Variable -File $File.FullName
    }

    Test-UpgradeToken -Token $Tokens -File $File.FullName
    Test-UpgradeManifest -File $File
}

function Test-WrapperUpgradeFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File
    )

    $LineNumber = 0
    foreach ($Line in Get-Content -Path $File.FullName) {
        $LineNumber++
        $TrimmedLine = $Line.Trim()
        if ([string]::IsNullOrWhiteSpace($TrimmedLine)) {
            continue
        }

        if ($TrimmedLine.StartsWith('#') -or $TrimmedLine.StartsWith('::') -or $TrimmedLine -match '^rem\s') {
            continue
        }

        if ($Line -match '\bpowershell(\.exe)?\b') {
            $Params = @{
                File = $File.FullName
                Line = $LineNumber
                Pattern = 'Wrapper runtime executable'
                Decision = 'UpdateRequired'
                Action = 'Review wrapper command and use pwsh where PowerShell 7.6+ is required.'
                Evidence = $Line
            }
            New-UpgradeFinding @Params
        }

        if ($Line -match '-ExecutionPolicy\s+Bypass') {
            $Params = @{
                File = $File.FullName
                Line = $LineNumber
                Pattern = 'Execution policy bypass'
                Decision = 'UpdateRequired'
                Action = 'Review whether the wrapper still needs an execution-policy bypass.'
                Evidence = $Line
            }
            New-UpgradeFinding @Params
        }

        if ($Line -match '[A-Z]:\\|\\\\[^\\]+\\[^\\]+') {
            $Params = @{
                File = $File.FullName
                Line = $LineNumber
                Pattern = 'Wrapper path assumption'
                Decision = 'UpdateRequired'
                Action = 'Review drive, UNC and working-directory assumptions for the PowerShell 7 host.'
                Evidence = $Line
            }
            New-UpgradeFinding @Params
        }
    }
}

function Test-UpgradeFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo] $File
    )

    if ($File.Extension.ToLowerInvariant() -in @('.ps1', '.psm1', '.psd1')) {
        Test-PowerShellUpgradeFile -File $File
        return
    }

    Test-WrapperUpgradeFile -File $File
}

try {
    $Files = @(Get-UpgradeScanFile -RootPath $Path -IncludeWrappers:$IncludeWrapperFiles.IsPresent)
    $Findings = foreach ($File in $Files) {
        Test-UpgradeFile -File $File
    }

    $Report = [pscustomobject]@{
        RootPath = (Resolve-Path -Path $Path).Path
        FileCount = $Files.Count
        FindingCount = @($Findings).Count
        Findings = @($Findings | Sort-Object -Property File, Line, Pattern)
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $Report | ConvertTo-Json -Depth 6 | Set-Content -Path $OutputPath -Encoding utf8
    }

    if ($Format -eq 'Json') {
        $Report | ConvertTo-Json -Depth 6
    } else {
        [pscustomobject]@{
            File = $Report.RootPath
            Line = 0
            Pattern = 'Summary'
            Decision = 'Scanned'
            Action = "Files: $($Report.FileCount). Findings: $($Report.FindingCount)."
            Evidence = 'Review each finding before changing code.'
        }

        $Report.Findings
    }

    exit 0
} catch {
    Write-Error -Message "Upgrade readiness scan failed. $($_.Exception.Message)"
    exit 1
}
