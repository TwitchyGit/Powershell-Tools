<#
.SYNOPSIS
    Tests the members of local groups on each component server.

.DESCRIPTION
    Groups come from the LocalGroups section of the settings. Default groups apply to
    every Windows server. Groups in ByRole apply to one role.
    For each group the check reports:
      - members that are not in the Allowed list (Fail or Warn, set by UnexpectedStatus)
      - entries in the Required list that are not members (Fail)
    Allowed and Required entries accept wildcards, for example 'EXAMPLE\svc-*'.

    This check only reads data. Simulation only stops the report files.

.PARAMETER Role
    Roles to test. Default is all Windows roles.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER Simulate
    Makes no changes. No report files are written.

.EXAMPLE
    .\Check-LocalGroupMembership.ps1 -Role PSM -Verbose
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

$ctx = Start-Check -Name 'LocalGroupMembership' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$probe = {
    param([string]$GroupName)
    $result = [pscustomobject]@{ Found = $true; Members = @(); Error = '' }
    try {
        $group = [ADSI]('WinNT://./{0},group' -f $GroupName)
        $names = foreach ($member in @($group.Invoke('Members'))) {
            $path = [string]$member.GetType().InvokeMember('ADsPath', 'GetProperty', $null, $member, $null)
            $parts = ($path -replace '^WinNT://', '') -split '/'
            if ($parts.Count -ge 2) { '{0}\{1}' -f $parts[-2], $parts[-1] } else { $parts[0] }
        }
        $result.Members = @($names)
    } catch {
        $result.Found = $false
        $result.Error = $_.Exception.Message
    }
    return $result
}

try {
    $cfg = (Get-CheckSettings).LocalGroups
    $unexpectedStatus = 'Fail'
    if ($cfg.UnexpectedStatus -eq 'Warn') { $unexpectedStatus = 'Warn' }

    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Testing local groups on {0} server(s)." -f $targets.Count)

    foreach ($t in $targets) {
        $groups = @($cfg.Default)
        if ($cfg.ByRole.ContainsKey($t.Role)) { $groups += @($cfg.ByRole[$t.Role]) }

        foreach ($rule in $groups) {
            $groupName = [string]$rule.Group
            try {
                $res = Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $probe -ArgumentList @($groupName) -Credential $RemoteCredential
            } catch {
                Add-Finding -Role $t.Role -Target $t.Host -Item $groupName -Status Error -Message $_.Exception.Message
                continue
            }

            if (-not $res.Found) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $groupName -Status Error -Message ('Cannot read group: {0}' -f $res.Error)
                continue
            }

            $members = @($res.Members | Where-Object { $_ })
            Write-CheckLog -Level Debug -Message ("{0} {1}: {2}" -f $t.Host, $groupName, ($members -join '; '))

            $unexpected = @($members | Where-Object { -not (Test-AnyLike -Value $_ -Pattern @($rule.Allowed)) })
            $missing = @()
            foreach ($required in @($rule.Required)) {
                if (-not $required) { continue }
                $hit = @($members | Where-Object { $_ -like $required })
                if ($hit.Count -eq 0) { $missing += $required }
            }

            if ($unexpected.Count -eq 0 -and $missing.Count -eq 0) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $groupName -Status Pass -Message ('{0} member(s). All expected.' -f $members.Count)
                continue
            }
            if ($unexpected.Count -gt 0) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $groupName -Status $unexpectedStatus `
                    -Message ('Unexpected member(s): {0}' -f ($unexpected -join '; '))
            }
            if ($missing.Count -gt 0) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $groupName -Status Fail `
                    -Message ('Required member(s) missing: {0}' -f ($missing -join '; '))
            }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
