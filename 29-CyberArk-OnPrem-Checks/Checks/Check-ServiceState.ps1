<#
.SYNOPSIS
    Tests that the Windows services of each component role are running.

.DESCRIPTION
    Service names come from the Services list of each role in the settings.
    A name can be a service name or a display name. Wildcards are allowed.
    A stopped service is a Fail. A missing service is a Fail.
    A start type that differs from ServiceState.ExpectedStartType is a Warn.

    With -Remediate the check starts stopped services.
    Simulation: -Remediate only reports which services it would start.

.PARAMETER Role
    Roles to test. Default is all Windows roles.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER Remediate
    Start services that are stopped.

.PARAMETER Simulate
    Makes no changes. No report files are written.

.EXAMPLE
    .\Check-ServiceState.ps1 -Role CPM -Verbose

.EXAMPLE
    .\Check-ServiceState.ps1 -Remediate -Simulate
#>
[CmdletBinding()]
param(
    [string[]]$Role,
    [string[]]$ComputerName,
    [switch]$Remediate,
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

$ctx = Start-Check -Name 'ServiceState' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$probe = {
    param([string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        $found = @(Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like $pattern -or $_.DisplayName -like $pattern })
        if ($found.Count -eq 0) {
            [pscustomobject]@{ Pattern = $pattern; Found = $false; Name = ''; Status = ''; StartType = '' }
        } else {
            foreach ($svc in $found) {
                [pscustomobject]@{
                    Pattern   = $pattern
                    Found     = $true
                    Name      = $svc.Name
                    Status    = [string]$svc.Status
                    StartType = [string]$svc.StartType
                }
            }
        }
    }
}

$starter = {
    param([string]$ServiceName)
    Start-Service -Name $ServiceName -ErrorAction Stop
    (Get-Service -Name $ServiceName -ErrorAction Stop).Status.ToString()
}

try {
    $expectedStart = [string](Get-CheckSettings).ServiceState.ExpectedStartType
    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Testing services on {0} server(s)." -f $targets.Count)

    foreach ($t in $targets) {
        $patterns = @((Get-RoleSettings -Role $t.Role).Services)
        if ($patterns.Count -eq 0) {
            Write-CheckLog -Level Verbose -Message ("Role {0} has no services set. Skipped {1}." -f $t.Role, $t.Host)
            continue
        }

        try {
            $rows = @(Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $probe -ArgumentList @(, [string[]]$patterns) -Credential $RemoteCredential)
        } catch {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'Service query' -Status Error -Message $_.Exception.Message
            continue
        }

        foreach ($row in $rows) {
            if (-not $row.Found) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $row.Pattern -Status Fail -Message 'Service not found.'
                continue
            }

            if ($row.Status -eq 'Running') {
                if ($expectedStart -and $row.StartType -ne $expectedStart) {
                    Add-Finding -Role $t.Role -Target $t.Host -Item $row.Name -Status Warn `
                        -Message ('Running. Start type is {0}. Expected {1}.' -f $row.StartType, $expectedStart)
                } else {
                    Add-Finding -Role $t.Role -Target $t.Host -Item $row.Name -Status Pass -Message 'Running.'
                }
                continue
            }

            if (-not $Remediate) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $row.Name -Status Fail -Message ('Status is {0}.' -f $row.Status)
                continue
            }

            if ($Simulate) {
                Write-CheckLog -Level Sim -Message ("Would start service '{0}' on {1}." -f $row.Name, $t.Host)
                Add-Finding -Role $t.Role -Target $t.Host -Item $row.Name -Status Fail `
                    -Message ('Status is {0}. Simulation: would start it.' -f $row.Status)
                continue
            }

            try {
                $newStatus = Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $starter -ArgumentList @($row.Name) -Credential $RemoteCredential
                if ("$newStatus" -eq 'Running') {
                    Add-Finding -Role $t.Role -Target $t.Host -Item $row.Name -Status Warn -Message 'Was stopped. The check started it.'
                } else {
                    Add-Finding -Role $t.Role -Target $t.Host -Item $row.Name -Status Fail -Message ('Start attempted. Status is {0}.' -f $newStatus)
                }
            } catch {
                Add-Finding -Role $t.Role -Target $t.Host -Item $row.Name -Status Fail -Message ('Start failed: {0}' -f $_.Exception.Message)
            }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
