#Requires -Version 5.1
<#
.SYNOPSIS
    The single settings and helper module for all on-premises CyberArk checks.

.DESCRIPTION
    Every check script imports this one file.
    Edit only the section named USER SETTINGS.
    The section named HELPER FUNCTIONS holds shared code. Change it only if you must.

    Set Configured to $true in the settings when you finish your edits.
    Live runs refuse to start until you do. Simulation runs only warn.

    To keep the settings outside the repository, set the environment variable
    ONPREM_CHECKS_SETTINGS to the full path of your own copy of this file.
#>

#region USER SETTINGS

$Script:Settings = @{

    # Set to $true after you edit this file.
    Configured  = $false

    # A short label for this environment. It is used in report and archive paths.
    Environment = 'DEV'

    Paths = @{
        # Reports and logs are written here. Each check makes its own sub folder.
        OutputRoot      = 'C:\ProgramData\OnPremChecks\Output'
        # Leave empty to use the Checks folder next to the Config folder.
        ChecksDirectory = ''
    }

    Security = @{
        # When $true, any report or archive path on a network share (UNC path or mapped
        # network drive) is refused. The checks then use no SMB file access at all.
        # All remote access uses PowerShell remoting (WinRM, TCP 5985 or 5986).
        BlockSmbPaths = $true
    }

    # Settings for PowerShell remoting (WinRM) to the component servers.
    Remoting = @{
        UseSsl              = $false
        Port                = 0          # 0 = use the default port
        Authentication      = 'Default'  # Default, Kerberos, Negotiate, Credssp and so on
        OpenTimeoutSec      = 20
        OperationTimeoutSec = 120
    }

    Network = @{
        TcpTimeoutMs  = 3000
        WebTimeoutSec = 30
        SlowResponseMs = 3000
    }

    # Order in which roles are processed when no -Role is given.
    RoleOrder = @('Vault', 'CPM', 'PVWA', 'PSM', 'CCP', 'Synchronizer', 'PSMP', 'PTA')

    # One block for each component role.
    #   Platform      Windows or Linux. Windows-only checks skip Linux roles.
    #   Hosts         Primary servers.
    #   StandbyHosts  Passive, DR or standby servers.
    #   VirtualHosts  Load balancer or cluster names. Only the endpoint check uses these.
    #   Services      Service names or display names (wildcards allowed).
    #   Ports         TCP ports that must accept a connection.
    #   HealthUrl     Optional URL for a web health probe. {host} is replaced by the server name.
    #   ParityPaths   Folders compared between servers of the same role.
    #   LogPaths      Folders that the log archive check copies from.
    # Confirm every service name, path and port against your own installation.
    Roles = @{

        Vault = @{
            Platform     = 'Windows'
            Hosts        = @('vault01.example.local')
            StandbyHosts = @('vault02.example.local')
            VirtualHosts = @()
            Services     = @('PrivateArk Server', 'CyberArk Logic Container')
            Ports        = @(1858)
            HealthUrl    = ''
            ParityPaths  = @()
            LogPaths     = @(
                @{ Path = 'C:\Program Files (x86)\PrivateArk\Server\Logs'; Recurse = $false }
            )
        }

        CPM = @{
            Platform     = 'Windows'
            Hosts        = @('cpm01.example.local')
            StandbyHosts = @('cpm02.example.local')
            VirtualHosts = @()
            Services     = @('CyberArk Password Manager', 'CyberArk Central Policy Manager Scanner')
            Ports        = @()
            HealthUrl    = ''
            ParityPaths  = @('C:\Program Files (x86)\CyberArk\Password Manager\bin')
            LogPaths     = @(
                @{ Path = 'C:\Program Files (x86)\CyberArk\Password Manager\Logs'; Recurse = $false }
            )
        }

        PVWA = @{
            Platform       = 'Windows'
            Hosts          = @('pvwa01.example.local', 'pvwa02.example.local')
            StandbyHosts   = @()
            VirtualHosts   = @('pvwa.example.local')
            Services       = @('W3SVC')
            Ports          = @(443)
            HealthUrl      = 'https://{host}/PasswordVault/API/Server/Verify'
            # When ApiLogon is $true the endpoint check opens and closes one API session.
            ApiLogon       = $true
            ApiBasePath    = '/PasswordVault/API'
            ApiAuthMethod  = 'CyberArk'
            ParityPaths    = @('C:\inetpub\wwwroot\PasswordVault')
            LogPaths       = @(
                @{ Path = 'C:\Windows\Temp\PVWA\Logs'; Recurse = $false }
            )
        }

        PSM = @{
            Platform     = 'Windows'
            Hosts        = @('psm01.example.local', 'psm02.example.local')
            StandbyHosts = @()
            VirtualHosts = @()
            Services     = @('Cyber-Ark Privileged Session Manager', 'TermService')
            Ports        = @(3389)
            HealthUrl    = ''
            ParityPaths  = @('C:\Program Files (x86)\CyberArk\PSM\Components')
            LogPaths     = @(
                @{ Path = 'C:\Program Files (x86)\CyberArk\PSM\Logs'; Recurse = $false }
            )
        }

        CCP = @{
            Platform     = 'Windows'
            Hosts        = @('ccp01.example.local')
            StandbyHosts = @()
            VirtualHosts = @()
            Services     = @('W3SVC')
            Ports        = @(443)
            HealthUrl    = ''
            ParityPaths  = @()
            LogPaths     = @()
        }

        Synchronizer = @{
            Platform     = 'Windows'
            Hosts        = @('sync01.example.local')
            StandbyHosts = @()
            VirtualHosts = @()
            Services     = @()
            Ports        = @()
            HealthUrl    = ''
            ParityPaths  = @()
            LogPaths     = @(
                @{ Path = 'C:\Program Files (x86)\CyberArk\Synchronizer\Logs'; Recurse = $false }
            )
        }

        PSMP = @{
            Platform     = 'Linux'
            Hosts        = @('psmp01.example.local')
            StandbyHosts = @()
            VirtualHosts = @()
            Services     = @()
            Ports        = @(22)
            HealthUrl    = ''
            ParityPaths  = @()
            LogPaths     = @()
        }

        PTA = @{
            Platform     = 'Linux'
            Hosts        = @('pta01.example.local')
            StandbyHosts = @()
            VirtualHosts = @()
            Services     = @()
            Ports        = @(443)
            HealthUrl    = ''
            ParityPaths  = @()
            LogPaths     = @()
        }
    }

    ServiceState = @{
        # A service with a different start type gets a warning. Leave empty to skip.
        ExpectedStartType = 'Automatic'
    }

    Storage = @{
        WarnFreePercent = 20
        FailFreePercent = 10
        WarnFreeGB      = 10
        FailFreeGB      = 5
        # Empty list = all fixed disks. Example: @('C:', 'D:')
        Drives          = @()
        # Per role threshold changes. Example: @{ Vault = @{ WarnFreePercent = 30; FailFreePercent = 15 } }
        RoleOverrides   = @{}
    }

    EventLog = @{
        Logs          = @('System', 'Application')
        # Extra logs for one role. Example: @{ PSM = @('Microsoft-Windows-TerminalServices-LocalSessionManager/Operational') }
        RoleLogs      = @{}
        LookbackHours = 24
        # 1 = Critical, 2 = Error, 3 = Warning
        Levels        = @(1, 2)
        MaxEvents     = 1000
        WarnAbove     = 0
        FailAbove     = 25
        TopGroups     = 5
        # Events to ignore. Provider accepts wildcards. Id is a list of event IDs.
        # Example: @(@{ Provider = 'Example-Provider'; Id = @(1000, 1001) })
        Ignore        = @()
    }

    EventCollect = @{
        Levels          = @(1, 2, 3)
        LookbackHours   = 24
        MaxEvents       = 2000
        MaxMessageChars = 1000
    }

    Licensing = @{
        # Roles that use Remote Desktop licensing.
        Roles                = @('PSM')
        ExpectedServers      = @('rdlicense01.example.local')
        # PerUser or PerDevice
        ExpectedMode         = 'PerUser'
        # Set to $null to skip the license count test.
        MinAvailableLicenses = 5
        # Port used to test that a license server can be reached.
        Port                 = 135
        # Used only when the server has no license server set.
        MinGraceDays         = 14
    }

    # Rules for configuration files. Types:
    #   Exists       The file must exist.
    #   Contains     The regular expression in Pattern must match.
    #   NotContains  The regular expression in Pattern must not match.
    #   KeyEquals    A line "Key=Value" must have the value in Value.
    #   XmlValue     The XPath result must equal Value.
    # Set Sensitive = $true to keep the actual value out of reports.
    ConfigRules = @(
        @{
            Role        = 'CPM'
            Path        = 'C:\Program Files (x86)\CyberArk\Password Manager\Vault\Vault.ini'
            Type        = 'KeyEquals'
            Key         = 'ADDRESS'
            Value       = 'vault.example.local'
            Description = 'CPM points to the expected Vault address'
        }
        @{
            Role        = 'PVWA'
            Path        = 'C:\inetpub\wwwroot\PasswordVault\web.config'
            Type        = 'XmlValue'
            XPath       = '//configuration/system.web/compilation/@debug'
            Value       = 'false'
            Description = 'PVWA debug compilation is off'
        }
        @{
            Role        = 'PSM'
            Path        = 'C:\Program Files (x86)\CyberArk\PSM\Vault\Vault.ini'
            Type        = 'Exists'
            Description = 'PSM Vault.ini exists'
        }
    )

    # Rules for installed product versions. NamePattern matches the name in Programs and Features.
    #   Minimum            The version must be at least this value. Leave empty to skip.
    #   Exact              The version must equal this value. Leave empty to skip.
    #   RequireConsistent  All servers of the role must report the same version.
    VersionRules = @(
        @{ Role = 'CPM';  NamePattern = 'CyberArk Password Manager*';        Minimum = '14.2.0'; Exact = ''; RequireConsistent = $true }
        @{ Role = 'PVWA'; NamePattern = 'CyberArk Password Vault Web Access*'; Minimum = '14.2.0'; Exact = ''; RequireConsistent = $true }
        @{ Role = 'PSM';  NamePattern = 'CyberArk Privileged Session Manager*'; Minimum = '14.2.0'; Exact = ''; RequireConsistent = $true }
    )

    Parity = @{
        # Roles compared when no -Role is given.
        Roles            = @('CPM', 'PVWA', 'PSM')
        # Patterns tested against the full file path.
        Exclude          = @('*.log', '*.tmp', '*.bak', '*\Logs\*', '*\Temp\*')
        # Files that are allowed to differ between servers. A difference is reported as Info.
        ExpectedToDiffer = @('Vault.ini', '*.config')
        MaxFiles         = 5000
        MaxHashMB        = 200
    }

    LocalGroups = @{
        # Groups checked on every Windows server.
        Default = @(
            @{ Group = 'Administrators'; Allowed = @('Administrator', 'EXAMPLE\Server-Admins'); Required = @() }
        )
        # Extra groups for one role.
        ByRole  = @{
            PSM = @(
                @{ Group = 'Remote Desktop Users'; Allowed = @('EXAMPLE\PSM-Operators'); Required = @() }
            )
        }
        # Status for a member that is not in the Allowed list. Fail or Warn.
        UnexpectedStatus = 'Fail'
    }

    Certificates = @{
        Stores                     = @('My')
        WarnDays                   = 45
        FailDays                   = 14
        OnlyWithPrivateKey         = $true
        IgnoreSubjects             = @()
        IgnoreThumbprints          = @()
        # Certificates that expired longer ago than this are ignored.
        IgnoreExpiredOlderThanDays = 90
    }

    LogArchive = @{
        # A local folder on the computer that runs the check. Files travel over WinRM.
        # UNC paths and mapped network drives are refused while Security.BlockSmbPaths is $true.
        DestinationRoot = 'D:\CheckLogs'
        AgeHours        = 24
        Include         = @('*.log', '*.txt')
        MaxFileMB       = 200
        # Size of each block read over WinRM.
        ChunkMB         = 4
    }

    Runner = @{
        MaxParallel           = 4
        CheckTimeoutMinutes   = 15
        TreatWarningAsFailure = $false
    }

    # Sets of checks for Run-Checks.ps1. Entry keys:
    #   Name                Label in reports.
    #   Script              File name in the Checks folder.
    #   Params              Extra parameters for the check.
    #   NeedsApiCredential  Pass -ApiCredential to this check.
    #   UsesRemoting        Pass -RemoteCredential to this check. Default is $true.
    #   IgnoreExitCode      Report the exit code but do not count a failure.
    Suites = @{

        Health = @(
            @{ Name = 'EndpointHealth';       Script = 'Check-EndpointHealth.ps1';       NeedsApiCredential = $true; UsesRemoting = $false }
            @{ Name = 'ServiceState';         Script = 'Check-ServiceState.ps1' }
            @{ Name = 'StorageCapacity';      Script = 'Check-StorageCapacity.ps1' }
            @{ Name = 'EventLogErrors';       Script = 'Check-EventLogErrors.ps1' }
            @{ Name = 'LicenseServer';        Script = 'Check-LicenseServer.ps1' }
            @{ Name = 'ConfigFiles';          Script = 'Check-ConfigFiles.ps1' }
            @{ Name = 'ComponentVersions';    Script = 'Check-ComponentVersions.ps1' }
            @{ Name = 'FileParity';           Script = 'Check-FileParity.ps1' }
            @{ Name = 'LocalGroupMembership'; Script = 'Check-LocalGroupMembership.ps1' }
            @{ Name = 'CertificateExpiry';    Script = 'Check-CertificateExpiry.ps1' }
        )

        Logs = @(
            @{ Name = 'EventLogCollect';  Script = 'Check-EventLogCollect.ps1' }
            @{ Name = 'LogArchive-CPM';   Script = 'Check-LogArchive.ps1'; Params = @{ Role = @('CPM') } }
            @{ Name = 'LogArchive-PSM';   Script = 'Check-LogArchive.ps1'; Params = @{ Role = @('PSM') } }
            @{ Name = 'LogArchive-PVWA';  Script = 'Check-LogArchive.ps1'; Params = @{ Role = @('PVWA') } }
            @{ Name = 'LogArchive-Sync';  Script = 'Check-LogArchive.ps1'; Params = @{ Role = @('Synchronizer') } }
        )
    }
}

#endregion USER SETTINGS


#region HELPER FUNCTIONS

$Script:ActiveContext = $null

function Get-CheckSettings {
    <# Returns the settings hashtable. #>
    return $Script:Settings
}

function Get-RoleSettings {
    param([Parameter(Mandatory)][string]$Role)
    if (-not $Script:Settings.Roles.ContainsKey($Role)) {
        throw ("Role '{0}' is not in the settings. Known roles: {1}." -f $Role, ($Script:Settings.RoleOrder -join ', '))
    }
    return $Script:Settings.Roles[$Role]
}

function Get-RoleNames {
    param([ValidateSet('Windows', 'Linux', 'Any')][string]$Platform = 'Any')
    foreach ($name in $Script:Settings.RoleOrder) {
        if (-not $Script:Settings.Roles.ContainsKey($name)) { continue }
        if ($Platform -eq 'Any' -or $Script:Settings.Roles[$name].Platform -eq $Platform) { $name }
    }
}

function Get-CheckTargets {
    <#
    Returns one object for each role and server. Each object has Role and Host.
    -ComputerName replaces the server list. It needs exactly one role.
    #>
    param(
        [string[]]$Role,
        [string[]]$ComputerName,
        [ValidateSet('Windows', 'Linux', 'Any')][string]$Platform = 'Any',
        [switch]$IncludeStandby,
        [switch]$IncludeVirtual
    )

    $names = @($Role | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($names.Count -eq 0) { $names = @(Get-RoleNames -Platform $Platform) }
    foreach ($n in $names) { [void](Get-RoleSettings -Role $n) }

    $override = @($ComputerName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($override.Count -gt 0 -and $names.Count -ne 1) {
        throw 'Use -Role with exactly one role when you use -ComputerName.'
    }

    $seen = @{}
    foreach ($n in $names) {
        $cfg = Get-RoleSettings -Role $n
        if ($Platform -ne 'Any' -and $cfg.Platform -ne $Platform) {
            Write-CheckLog -Level Verbose -Message ("Role {0} is a {1} role. Skipped for this check." -f $n, $cfg.Platform)
            continue
        }
        $list = @()
        if ($override.Count -gt 0) {
            $list = $override
        } else {
            $list += @($cfg.Hosts)
            if ($IncludeStandby) { $list += @($cfg.StandbyHosts) }
            if ($IncludeVirtual) { $list += @($cfg.VirtualHosts) }
        }
        foreach ($item in $list) {
            $serverName = ([string]$item).Trim()
            if (-not $serverName) { continue }
            $key = '{0}|{1}' -f $n, $serverName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            [pscustomobject]@{ Role = $n; Host = $serverName }
        }
    }
}

function Write-CheckLog {
    <# Writes one log line to the console and keeps it for the log file. #>
    param(
        [ValidateSet('Info', 'Warn', 'Error', 'Verbose', 'Debug', 'Sim')][string]$Level = 'Info',
        [Parameter(Mandatory, Position = 0)][string]$Message
    )

    $ctx = $Script:ActiveContext
    if ($null -ne $ctx) {
        if ($Level -eq 'Verbose' -and -not ($ctx.Verbose -or $ctx.Debug)) { return }
        if ($Level -eq 'Debug' -and -not $ctx.Debug) { return }
    } elseif ($Level -in @('Verbose', 'Debug')) {
        return
    }

    $tag = @{ Info = 'INFO'; Warn = 'WARN'; Error = 'ERROR'; Verbose = 'VERBOSE'; Debug = 'DEBUG'; Sim = 'SIMULATE' }[$Level]
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $tag, $Message
    Write-Host $line
    if ($null -ne $ctx) { [void]$ctx.LogLines.Add($line) }
}

function Start-Check {
    <#
    Starts a check and returns the check context.
    Pass $PSBoundParameters to -Bound so the function can see -Verbose and -Debug.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$Simulate,
        [System.Collections.IDictionary]$Bound = @{},
        [string]$OutputDirectory
    )

    $isDebug = $false
    $isVerbose = $false
    if ($Bound.Contains('Debug'))   { $isDebug = [bool]$Bound['Debug'] }
    if ($Bound.Contains('Verbose')) { $isVerbose = [bool]$Bound['Verbose'] }
    if ($isDebug) { $isVerbose = $true }

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $OutputDirectory = Join-Path -Path $Script:Settings.Paths.OutputRoot -ChildPath $Name
    }

    Assert-NotSmbPath -Path $OutputDirectory -Name 'Output folder'

    $ctx = [pscustomobject]@{
        Name            = $Name
        Simulate        = [bool]$Simulate
        Verbose         = $isVerbose
        Debug           = $isDebug
        StartTime       = Get-Date
        OutputDirectory = $OutputDirectory
        Findings        = New-Object System.Collections.ArrayList
        LogLines        = New-Object System.Collections.ArrayList
    }
    $Script:ActiveContext = $ctx

    Write-CheckLog -Level Info -Message ("Check '{0}' started. Environment: {1}. Computer: {2}." -f $Name, $Script:Settings.Environment, $env:COMPUTERNAME)
    if ($ctx.Simulate) {
        Write-CheckLog -Level Sim -Message 'Simulation is on. This run makes no changes.'
    }

    if (-not $Script:Settings.Configured) {
        if ($ctx.Simulate) {
            Write-CheckLog -Level Warn -Message 'The settings file is not marked as configured. Results use placeholder values.'
        } else {
            throw 'The settings file is not marked as configured. Edit Config\CheckSettings.psm1 and set Configured to $true.'
        }
    }
    return $ctx
}

function Add-Finding {
    <# Adds one result row to the active check. #>
    param(
        [string]$Role = '',
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string]$Item,
        [Parameter(Mandatory)][ValidateSet('Pass', 'Info', 'Warn', 'Fail', 'Error', 'Skipped')][string]$Status,
        [string]$Message = ''
    )

    $ctx = $Script:ActiveContext
    if ($null -eq $ctx) { throw 'Call Start-Check before Add-Finding.' }

    $row = [pscustomobject][ordered]@{
        Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Check     = $ctx.Name
        Role      = $Role
        Target    = $Target
        Item      = $Item
        Status    = $Status
        Message   = $Message
    }
    [void]$ctx.Findings.Add($row)
    Write-CheckLog -Level Verbose -Message ('{0} | {1} | {2} | {3} | {4}' -f $Status, $Role, $Target, $Item, $Message)
}

function Complete-Check {
    <#
    Prints the summary, writes the CSV and log files (not in simulation) and returns the exit code.
    0 = no failures. 1 = at least one Fail or Error. Warnings fail the run only if the settings say so.
    #>
    $ctx = $Script:ActiveContext
    if ($null -eq $ctx) { throw 'Call Start-Check before Complete-Check.' }

    $findings = @($ctx.Findings)
    $count = @{}
    foreach ($s in 'Pass', 'Info', 'Skipped', 'Warn', 'Fail', 'Error') {
        $count[$s] = @($findings | Where-Object { $_.Status -eq $s }).Count
    }

    $visible = $findings
    if (-not ($ctx.Verbose -or $ctx.Debug)) {
        $visible = @($findings | Where-Object { $_.Status -ne 'Pass' })
    }
    if ($visible.Count -gt 0) {
        $table = $visible | Format-Table -Property Role, Target, Item, Status, Message -AutoSize -Wrap | Out-String -Width 250
        Write-Host $table
    }

    $parts = foreach ($s in 'Pass', 'Info', 'Skipped', 'Warn', 'Fail', 'Error') { '{0}={1}' -f $s, $count[$s] }
    Write-CheckLog -Level Info -Message ("Result for '{0}': {1}" -f $ctx.Name, ($parts -join ' '))

    $stamp = '{0:yyyyMMdd_HHmmss}_{1}' -f $ctx.StartTime, $PID
    $csvPath = Join-Path -Path $ctx.OutputDirectory -ChildPath ('{0}_{1}.csv' -f $ctx.Name, $stamp)
    $logPath = Join-Path -Path $ctx.OutputDirectory -ChildPath ('{0}_{1}.log' -f $ctx.Name, $stamp)

    if ($ctx.Simulate) {
        Write-CheckLog -Level Sim -Message ("Would write report to '{0}' and log to '{1}'." -f $csvPath, $logPath)
    } else {
        try {
            if (-not (Test-Path -LiteralPath $ctx.OutputDirectory)) {
                New-Item -ItemType Directory -Path $ctx.OutputDirectory -Force -ErrorAction Stop | Out-Null
            }
            if ($findings.Count -gt 0) {
                $findings | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
            }
            Write-CheckLog -Level Info -Message ("Report: {0}" -f $csvPath)
            $elapsed = (Get-Date) - $ctx.StartTime
            Write-CheckLog -Level Info -Message ("Check '{0}' finished in {1:N1} seconds." -f $ctx.Name, $elapsed.TotalSeconds)
            $ctx.LogLines | Set-Content -LiteralPath $logPath -Encoding UTF8 -ErrorAction Stop
        } catch {
            Write-CheckLog -Level Warn -Message ("Could not write report files: {0}" -f $_.Exception.Message)
        }
    }

    $failed = $count['Fail'] + $count['Error']
    if ($Script:Settings.Runner.TreatWarningAsFailure) { $failed += $count['Warn'] }
    if ($failed -gt 0) { return 1 }
    return 0
}

function Test-LocalTarget {
    param([Parameter(Mandatory)][string]$ComputerName)
    $short = ($ComputerName -split '\.')[0]
    return (($ComputerName -in @('.', 'localhost', '127.0.0.1')) -or ($short -ieq $env:COMPUTERNAME))
}

function Invoke-OnTarget {
    <# Runs a script block on a server. The local computer runs it directly. #>
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @(),
        [pscredential]$Credential
    )

    if (Test-LocalTarget -ComputerName $ComputerName) {
        Write-CheckLog -Level Debug -Message ("Running locally for {0}." -f $ComputerName)
        return (Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList)
    }

    $splat = Get-RemotingParameters -ComputerName $ComputerName -Credential $Credential
    $splat['ScriptBlock'] = $ScriptBlock
    $splat['ArgumentList'] = $ArgumentList

    Write-CheckLog -Level Debug -Message ("Remote call to {0} over WinRM." -f $ComputerName)
    return (Invoke-Command @splat)
}

function Get-RemotingParameters {
    <# Builds the parameters that Invoke-Command and New-PSSession share. WinRM only. #>
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [pscredential]$Credential
    )
    $remoting = $Script:Settings.Remoting
    $splat = @{
        ComputerName  = $ComputerName
        SessionOption = (New-PSSessionOption -OpenTimeout ($remoting.OpenTimeoutSec * 1000) `
            -OperationTimeout ($remoting.OperationTimeoutSec * 1000))
        ErrorAction   = 'Stop'
    }
    if ($remoting.UseSsl) { $splat['UseSSL'] = $true }
    if ($remoting.Port -gt 0) { $splat['Port'] = $remoting.Port }
    if ($remoting.Authentication) { $splat['Authentication'] = $remoting.Authentication }
    if ($Credential) { $splat['Credential'] = $Credential }
    return $splat
}

function New-TargetSession {
    <# Opens a WinRM session to a server. Returns $null for the local computer. #>
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [pscredential]$Credential
    )
    if (Test-LocalTarget -ComputerName $ComputerName) { return $null }
    $splat = Get-RemotingParameters -ComputerName $ComputerName -Credential $Credential
    Write-CheckLog -Level Debug -Message ("Opening WinRM session to {0}." -f $ComputerName)
    return (New-PSSession @splat)
}

function Invoke-OnSession {
    <# Runs a script block in an open session. With no session it runs on the local computer. #>
    param(
        $Session,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList = @()
    )
    if ($null -eq $Session) {
        return (Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList)
    }
    return (Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop)
}

function Receive-RemoteFile {
    <#
    Copies a file from a server to a local path over a WinRM session, in blocks.
    The source file can be open for writing by another process.
    Returns the number of bytes written.
    #>
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$RemotePath,
        [Parameter(Mandatory)][string]$Destination,
        [int]$ChunkBytes = 4194304
    )

    $reader = {
        param([string]$Path, [int64]$Offset, [int]$Count)
        $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            [void]$stream.Seek($Offset, [System.IO.SeekOrigin]::Begin)
            $buffer = New-Object byte[] $Count
            $read = $stream.Read($buffer, 0, $Count)
            if ($read -lt $Count) {
                $trimmed = New-Object byte[] $read
                [Array]::Copy($buffer, $trimmed, $read)
                $buffer = $trimmed
            }
            , $buffer
        } finally {
            $stream.Dispose()
        }
    }

    $out = New-Object System.IO.FileStream($Destination, [System.IO.FileMode]::Create,
        [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $total = [int64]0
    try {
        while ($true) {
            $chunk = Invoke-Command -Session $Session -ScriptBlock $reader -ArgumentList $RemotePath, $total, $ChunkBytes -ErrorAction Stop
            if ($null -eq $chunk -or $chunk.Length -eq 0) { break }
            $out.Write($chunk, 0, $chunk.Length)
            $total += $chunk.Length
            if ($chunk.Length -lt $ChunkBytes) { break }
        }
    } finally {
        $out.Dispose()
    }
    return $total
}

function Test-SmbPath {
    <# Returns $true if the path is a UNC path or is on a mapped network drive. #>
    param([Parameter(Mandatory)][string]$Path)
    if ($Path -match '^(\\\\|//)') { return $true }
    if ($Path -match '^([A-Za-z]):') {
        try {
            $drive = New-Object System.IO.DriveInfo($Matches[1])
            return ($drive.DriveType -eq [System.IO.DriveType]::Network)
        } catch {
            return $false
        }
    }
    return $false
}

function Assert-NotSmbPath {
    <# Stops the check if the path is a network share and the settings block SMB. #>
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if ($Script:Settings.Security.BlockSmbPaths -and (Test-SmbPath -Path $Path)) {
        throw ("{0} '{1}' is on a network share. Security.BlockSmbPaths is on, so SMB paths are refused. Use a local folder." -f $Name, $Path)
    }
}

function Test-TcpPort {
    param(
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 3000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $async = $client.BeginConnect($ComputerName, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs, $false)) {
            Write-CheckLog -Level Debug -Message ("TCP {0}:{1} timed out." -f $ComputerName, $Port)
            return $false
        }
        $client.EndConnect($async)
        return $true
    } catch {
        Write-CheckLog -Level Debug -Message ("TCP {0}:{1} failed: {2}" -f $ComputerName, $Port, $_.Exception.Message)
        return $false
    } finally {
        $client.Close()
    }
}

function Resolve-HostAddress {
    <# Returns the addresses for a name, or $null if the name does not resolve. #>
    param([Parameter(Mandatory)][string]$ComputerName)
    try {
        $addresses = [System.Net.Dns]::GetHostAddresses($ComputerName)
        return @($addresses | ForEach-Object { $_.IPAddressToString })
    } catch {
        Write-CheckLog -Level Debug -Message ("DNS lookup for {0} failed: {1}" -f $ComputerName, $_.Exception.Message)
        return $null
    }
}

function ConvertTo-SafeVersion {
    <# Reads the first version number in a text. Returns $null if there is none. #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    $match = [regex]::Match($Text, '\d+(\.\d+){0,3}')
    if (-not $match.Success) { return $null }
    $value = $match.Value
    if ($value -notmatch '\.') { $value = $value + '.0' }
    try { return [version]$value } catch { return $null }
}

function Test-AnyLike {
    param([string]$Value, [string[]]$Pattern)
    foreach ($p in @($Pattern)) {
        if (-not [string]::IsNullOrEmpty($p) -and $Value -like $p) { return $true }
    }
    return $false
}

function Copy-FileShared {
    <# Copies a file that another process may have open for writing. #>
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    $inStream = $null
    $outStream = $null
    try {
        $inStream = New-Object System.IO.FileStream($Source, [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $outStream = New-Object System.IO.FileStream($Destination, [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $inStream.CopyTo($outStream)
    } finally {
        if ($null -ne $outStream) { $outStream.Dispose() }
        if ($null -ne $inStream) { $inStream.Dispose() }
    }
}

Export-ModuleMember -Function Get-CheckSettings, Get-RoleSettings, Get-RoleNames, Get-CheckTargets,
    Write-CheckLog, Start-Check, Add-Finding, Complete-Check, Test-LocalTarget, Invoke-OnTarget,
    Test-TcpPort, Resolve-HostAddress, ConvertTo-SafeVersion, Test-AnyLike, Copy-FileShared,
    Get-RemotingParameters, New-TargetSession, Invoke-OnSession, Receive-RemoteFile, Test-SmbPath, Assert-NotSmbPath

#endregion HELPER FUNCTIONS
