<#
.SYNOPSIS
    Tests the Remote Desktop licensing set-up on session host servers.

.DESCRIPTION
    For each server in the roles named in Licensing.Roles the check reads:
      - the licensing mode (per user or per device)
      - the list of license servers
      - the grace period days, if no license server is set
    Then it tests:
      - the mode equals Licensing.ExpectedMode
      - each configured license server is in Licensing.ExpectedServers
      - each license server answers on Licensing.Port
      - the license servers hold at least Licensing.MinAvailableLicenses free licenses
    The license count adds up all installed license packs. It is a coarse test.

    This check only reads data. Simulation only stops the report files.

.PARAMETER Role
    Roles to test. Default is Licensing.Roles from the settings.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER Simulate
    Makes no changes. No report files are written.

.EXAMPLE
    .\Check-LicenseServer.ps1 -Verbose
#>
[CmdletBinding()]
param(
    [string[]]$Role,
    [string[]]$ComputerName,
    [switch]$Simulate,
    [pscredential]$RemoteCredential,
    [string]$OutputDirectory
)

if ($PSBoundParameters.ContainsKey('Debug')) { $DebugPreference = 'SilentlyContinue' }

$settingsModule = $env:ONPREM_CHECKS_SETTINGS
if ([string]::IsNullOrWhiteSpace($settingsModule)) {
    $settingsModule = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Config\CheckSettings.psm1'
}
Import-Module -Name $settingsModule -Force -ErrorAction Stop

$ctx = Start-Check -Name 'LicenseServer' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$hostProbe = {
    $setting = Get-CimInstance -Namespace 'root/cimv2/TerminalServices' -ClassName Win32_TerminalServiceSetting -ErrorAction Stop
    $servers = @()
    $list = Invoke-CimMethod -InputObject $setting -MethodName GetSpecifiedLicenseServerList -ErrorAction SilentlyContinue
    if ($list -and $list.SpecifiedLSList) { $servers = @($list.SpecifiedLSList) }
    $grace = $null
    $days = Invoke-CimMethod -InputObject $setting -MethodName GetGracePeriodDays -ErrorAction SilentlyContinue
    if ($days) { $grace = $days.DaysLeft }
    [pscustomobject]@{ LicensingType = [int]$setting.LicensingType; Servers = $servers; GraceDays = $grace }
}

$packProbe = {
    Get-CimInstance -Namespace 'root/cimv2' -ClassName Win32_TSLicenseKeyPack -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{ Description = [string]$_.Description; Total = [int]$_.TotalLicenses; Available = [int]$_.AvailableLicenses }
    }
}

$modeNames = @{ 0 = 'Personal'; 1 = 'RemoteAdmin'; 2 = 'PerDevice'; 4 = 'PerUser'; 5 = 'NotConfigured' }

try {
    $settings = Get-CheckSettings
    $cfg = $settings.Licensing
    $roles = @($Role)
    if (@($roles | Where-Object { $_ }).Count -eq 0) { $roles = @($cfg.Roles) }

    $targets = @(Get-CheckTargets -Role $roles -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Testing licensing on {0} server(s)." -f $targets.Count)

    $licenseServers = @{}
    $expected = @($cfg.ExpectedServers | ForEach-Object { ([string]$_).ToLowerInvariant() })

    foreach ($t in $targets) {
        try {
            $info = Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $hostProbe -Credential $RemoteCredential
        } catch {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'Licensing query' -Status Error -Message $_.Exception.Message
            continue
        }

        $modeName = $modeNames[[int]$info.LicensingType]
        if (-not $modeName) { $modeName = 'Unknown ({0})' -f $info.LicensingType }
        if ($cfg.ExpectedMode -and $modeName -ne $cfg.ExpectedMode) {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'Licensing mode' -Status Fail `
                -Message ('Mode is {0}. Expected {1}.' -f $modeName, $cfg.ExpectedMode)
        } else {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'Licensing mode' -Status Pass -Message $modeName
        }

        $servers = @($info.Servers | Where-Object { $_ })
        if ($servers.Count -eq 0) {
            $graceText = 'unknown'
            if ($null -ne $info.GraceDays) { $graceText = [string]$info.GraceDays }
            if ($null -ne $info.GraceDays -and [int]$info.GraceDays -ge $cfg.MinGraceDays) {
                Add-Finding -Role $t.Role -Target $t.Host -Item 'License server' -Status Warn `
                    -Message ('No license server is set. Grace period days left: {0}.' -f $graceText)
            } else {
                Add-Finding -Role $t.Role -Target $t.Host -Item 'License server' -Status Fail `
                    -Message ('No license server is set. Grace period days left: {0}.' -f $graceText)
            }
            continue
        }

        foreach ($server in $servers) {
            $licenseServers[([string]$server).ToLowerInvariant()] = [string]$server
            if ($expected.Count -gt 0 -and ([string]$server).ToLowerInvariant() -notin $expected) {
                Add-Finding -Role $t.Role -Target $t.Host -Item ('License server {0}' -f $server) -Status Fail -Message 'Server is not in the expected list.'
            } elseif (Test-TcpPort -ComputerName ([string]$server) -Port ([int]$cfg.Port) -TimeoutMs ((Get-CheckSettings).Network.TcpTimeoutMs)) {
                Add-Finding -Role $t.Role -Target $t.Host -Item ('License server {0}' -f $server) -Status Pass -Message ('Reachable on port {0}.' -f $cfg.Port)
            } else {
                Add-Finding -Role $t.Role -Target $t.Host -Item ('License server {0}' -f $server) -Status Fail -Message ('Not reachable on port {0}.' -f $cfg.Port)
            }
        }
    }

    if ($null -ne $cfg.MinAvailableLicenses) {
        foreach ($server in $licenseServers.Values) {
            try {
                $packs = @(Invoke-OnTarget -ComputerName $server -ScriptBlock $packProbe -Credential $RemoteCredential)
                $available = ($packs | Measure-Object -Property Available -Sum).Sum
                $total = ($packs | Measure-Object -Property Total -Sum).Sum
                if ($null -eq $available) { $available = 0 }
                if ($null -eq $total) { $total = 0 }
                $text = '{0} of {1} license(s) free in {2} pack(s).' -f $available, $total, $packs.Count
                if ($available -lt $cfg.MinAvailableLicenses) {
                    Add-Finding -Role 'LicenseServer' -Target $server -Item 'Free licenses' -Status Fail -Message $text
                } else {
                    Add-Finding -Role 'LicenseServer' -Target $server -Item 'Free licenses' -Status Pass -Message $text
                }
            } catch {
                Add-Finding -Role 'LicenseServer' -Target $server -Item 'Free licenses' -Status Warn `
                    -Message ('Could not read license packs: {0}' -f $_.Exception.Message)
            }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
