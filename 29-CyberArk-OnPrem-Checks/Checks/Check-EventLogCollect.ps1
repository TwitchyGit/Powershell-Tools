<#
.SYNOPSIS
    Exports recent event log entries from each component server to CSV files.

.DESCRIPTION
    Logs come from the EventLog section of the settings. Levels, look-back time and limits
    come from the EventCollect section.
    Files are written to <OutputDirectory>\<server>\<log>.csv.

    Simulation: the check reads the events and reports how many it would export.
    It writes no files.

.PARAMETER Role
    Roles to collect from. Default is all Windows roles.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER Simulate
    Makes no changes. No CSV, report or log files are written.

.EXAMPLE
    .\Check-EventLogCollect.ps1 -Role CPM -OutputDirectory D:\Collect

.EXAMPLE
    .\Check-EventLogCollect.ps1 -Simulate -Verbose
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

$ctx = Start-Check -Name 'EventLogCollect' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$probe = {
    param([string]$LogName, [datetime]$Since, [int[]]$Levels, [int]$MaxEvents, [int]$MaxChars)

    if (-not (Get-WinEvent -ListLog $LogName -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ LogFound = $false; Rows = @() }
    }

    $events = @()
    try {
        $filter = @{ LogName = $LogName; Level = $Levels; StartTime = $Since }
        $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop)
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
    }

    $rows = foreach ($e in $events) {
        $text = ([string]$e.Message) -replace '\s+', ' '
        if ($text.Length -gt $MaxChars) { $text = $text.Substring(0, $MaxChars) }
        [pscustomobject]@{
            TimeCreated = $e.TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
            Level       = [string]$e.LevelDisplayName
            Provider    = [string]$e.ProviderName
            EventId     = [int]$e.Id
            Message     = $text
        }
    }
    return [pscustomobject]@{ LogFound = $true; Rows = @($rows) }
}

try {
    $settings = Get-CheckSettings
    $cfg = $settings.EventLog
    $collect = $settings.EventCollect
    $since = (Get-Date).AddHours(-1 * $collect.LookbackHours)

    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Collecting events from {0} server(s)." -f $targets.Count)

    foreach ($t in $targets) {
        $logs = @($cfg.Logs)
        if ($cfg.RoleLogs.ContainsKey($t.Role)) { $logs += @($cfg.RoleLogs[$t.Role]) }
        $logs = @($logs | Select-Object -Unique)

        foreach ($log in $logs) {
            try {
                $arguments = @($log, $since, [int[]]@($collect.Levels), [int]$collect.MaxEvents, [int]$collect.MaxMessageChars)
                $res = Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $probe -ArgumentList $arguments -Credential $RemoteCredential
            } catch {
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Error -Message $_.Exception.Message
                continue
            }

            if (-not $res.LogFound) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Skipped -Message 'Log does not exist on this server.'
                continue
            }

            $rows = @($res.Rows)
            $safeLog = $log -replace '[\\/:*?"<>|]', '_'
            $folder = Join-Path -Path $ctx.OutputDirectory -ChildPath $t.Host
            $file = Join-Path -Path $folder -ChildPath ('{0}.csv' -f $safeLog)

            if ($rows.Count -eq 0) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Pass -Message 'No events in the period. No file needed.'
                continue
            }

            if ($Simulate) {
                Write-CheckLog -Level Sim -Message ("Would write {0} event(s) to '{1}'." -f $rows.Count, $file)
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Info -Message ('Simulation. {0} event(s) would be exported.' -f $rows.Count)
                continue
            }

            try {
                if (-not (Test-Path -LiteralPath $folder)) {
                    New-Item -ItemType Directory -Path $folder -Force -ErrorAction Stop | Out-Null
                }
                $rows | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Pass -Message ('{0} event(s) written to {1}' -f $rows.Count, $file)
            } catch {
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Fail -Message ('Could not write file: {0}' -f $_.Exception.Message)
            }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
