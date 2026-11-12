<#
.SYNOPSIS
    Counts recent error events in the Windows event logs of each component server.

.DESCRIPTION
    Logs, levels, look-back time and limits come from the EventLog section of the settings.
    Events that match an Ignore rule are not counted.
    The result for each log is Pass, Warn or Fail, based on WarnAbove and FailAbove.
    The most frequent events (TopGroups) are also listed as Info rows.
    This check only reads data. Simulation only stops the report files.

.PARAMETER Role
    Roles to test. Default is all Windows roles.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER LookbackHours
    Overrides EventLog.LookbackHours.

.PARAMETER Simulate
    Makes no changes. No report files are written.

.EXAMPLE
    .\Check-EventLogErrors.ps1 -Role PSM -LookbackHours 48 -Verbose
#>
[CmdletBinding()]
param(
    [string[]]$Role,
    [string[]]$ComputerName,
    [int]$LookbackHours,
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

$ctx = Start-Check -Name 'EventLogErrors' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$probe = {
    param([string]$LogName, [datetime]$Since, [int[]]$Levels, [int]$MaxEvents, [object[]]$Ignore)

    $result = [pscustomobject]@{ LogFound = $true; Total = 0; Truncated = $false; Groups = @() }
    if (-not (Get-WinEvent -ListLog $LogName -ErrorAction SilentlyContinue)) {
        $result.LogFound = $false
        return $result
    }

    $events = @()
    try {
        $filter = @{ LogName = $LogName; Level = $Levels; StartTime = $Since }
        $events = @(Get-WinEvent -FilterHashtable $filter -MaxEvents $MaxEvents -ErrorAction Stop)
    } catch {
        if ($_.FullyQualifiedErrorId -notlike 'NoMatchingEventsFound*') { throw }
    }
    $result.Truncated = ($events.Count -ge $MaxEvents)

    $kept = @()
    foreach ($e in $events) {
        $skip = $false
        foreach ($rule in @($Ignore)) {
            if ($null -eq $rule) { continue }
            $providerOk = (-not $rule.Provider) -or ($e.ProviderName -like $rule.Provider)
            $idOk = (-not $rule.Id) -or (@($rule.Id) -contains [int]$e.Id)
            if ($providerOk -and $idOk) { $skip = $true; break }
        }
        if (-not $skip) { $kept += $e }
    }
    $result.Total = $kept.Count

    $groups = @()
    foreach ($g in ($kept | Group-Object -Property ProviderName, Id | Sort-Object -Property Count -Descending)) {
        $first = $g.Group[0]
        $text = ([string]$first.Message) -replace '\s+', ' '
        if ($text.Length -gt 200) { $text = $text.Substring(0, 200) }
        $groups += [pscustomobject]@{
            Provider = [string]$first.ProviderName
            Id       = [int]$first.Id
            Count    = [int]$g.Count
            Last     = ($g.Group | Sort-Object -Property TimeCreated -Descending | Select-Object -First 1).TimeCreated.ToString('yyyy-MM-dd HH:mm:ss')
            Sample   = $text
        }
    }
    $result.Groups = $groups
    return $result
}

try {
    $cfg = (Get-CheckSettings).EventLog
    $hours = $cfg.LookbackHours
    if ($PSBoundParameters.ContainsKey('LookbackHours') -and $LookbackHours -gt 0) { $hours = $LookbackHours }
    $since = (Get-Date).AddHours(-1 * $hours)
    Write-CheckLog -Level Verbose -Message ("Looking back {0} hour(s), since {1:yyyy-MM-dd HH:mm}." -f $hours, $since)

    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Reading event logs on {0} server(s)." -f $targets.Count)

    foreach ($t in $targets) {
        $logs = @($cfg.Logs)
        if ($cfg.RoleLogs.ContainsKey($t.Role)) { $logs += @($cfg.RoleLogs[$t.Role]) }
        $logs = @($logs | Select-Object -Unique)

        foreach ($log in $logs) {
            try {
                $arguments = @($log, $since, [int[]]@($cfg.Levels), [int]$cfg.MaxEvents, [object[]]@($cfg.Ignore))
                $res = Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $probe -ArgumentList $arguments -Credential $RemoteCredential
            } catch {
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Error -Message $_.Exception.Message
                continue
            }

            if (-not $res.LogFound) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Skipped -Message 'Log does not exist on this server.'
                continue
            }

            $note = ''
            if ($res.Truncated) { $note = (' Count is capped at {0} events.' -f $cfg.MaxEvents) }
            $text = '{0} matching event(s).{1}' -f $res.Total, $note

            if ($res.Total -gt $cfg.FailAbove) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Fail -Message $text
            } elseif ($res.Total -gt $cfg.WarnAbove) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Warn -Message $text
            } else {
                Add-Finding -Role $t.Role -Target $t.Host -Item $log -Status Pass -Message $text
            }

            foreach ($g in @($res.Groups | Select-Object -First $cfg.TopGroups)) {
                Add-Finding -Role $t.Role -Target $t.Host -Item ('{0}: {1} / {2}' -f $log, $g.Provider, $g.Id) -Status Info `
                    -Message ('{0} time(s). Last {1}. {2}' -f $g.Count, $g.Last, $g.Sample)
            }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
