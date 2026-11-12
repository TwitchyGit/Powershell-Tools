<#
.SYNOPSIS
    Tests that each component server can be reached and answers on its service ports.

.DESCRIPTION
    For each server the check does these tests:
      1. DNS lookup.
      2. TCP connection to each port set for the role.
      3. Web health probe, if the role has a HealthUrl.
      4. API session test (logon then logoff), if the role has ApiLogon set to $true.
    The session test uses a concurrent session. It does not end sessions of other users.

    Simulation: tests 1 to 3 only read data, so they run. Test 4 opens a session, so
    simulation skips it and only reports what it would do.

.PARAMETER Role
    Roles to test. Default is all roles in the settings.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER ApiCredential
    Account for the API session test. Without it, the session test is skipped.

.PARAMETER Simulate
    Makes no changes. No API session is opened. No report files are written.

.EXAMPLE
    .\Check-EndpointHealth.ps1 -Role PVWA -ApiCredential (Get-Credential) -Verbose

.EXAMPLE
    .\Check-EndpointHealth.ps1 -Simulate -Debug
#>
[CmdletBinding()]
param(
    [string[]]$Role,
    [string[]]$ComputerName,
    [pscredential]$ApiCredential,
    [switch]$Simulate,
    [string]$OutputDirectory
)

if ($PSBoundParameters.ContainsKey('Debug')) { $DebugPreference = 'SilentlyContinue' }

$settingsModule = $env:ONPREM_CHECKS_SETTINGS
if ([string]::IsNullOrWhiteSpace($settingsModule)) {
    $settingsModule = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Config\CheckSettings.psm1'
}
Import-Module -Name $settingsModule -Force -ErrorAction Stop

$ctx = Start-Check -Name 'EndpointHealth' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

function Test-ApiSession {
    # Opens one API session and closes it. Returns an object with the result.
    param(
        [string]$HostName,
        [hashtable]$RoleSettings,
        [pscredential]$Credential,
        [int]$TimeoutSec
    )

    $basePath = [string]$RoleSettings.ApiBasePath
    if (-not $basePath) { $basePath = '/PasswordVault/API' }
    $method = [string]$RoleSettings.ApiAuthMethod
    if (-not $method) { $method = 'CyberArk' }

    $logonUri = 'https://{0}{1}/auth/{2}/Logon' -f $HostName, $basePath, $method
    $logoffUri = 'https://{0}{1}/Auth/Logoff' -f $HostName, $basePath

    $payload = @{
        username          = $Credential.UserName
        password          = $Credential.GetNetworkCredential().Password
        concurrentSession = $true
    }
    $body = $payload | ConvertTo-Json
    $payload = $null

    $token = $null
    try {
        Write-CheckLog -Level Debug -Message ("POST {0}" -f $logonUri)
        $token = Invoke-RestMethod -Method Post -Uri $logonUri -ContentType 'application/json' `
            -Body $body -TimeoutSec $TimeoutSec -ErrorAction Stop
    } catch {
        return [pscustomobject]@{ LogonOk = $false; LogoffOk = $false; Message = ('Logon failed: {0}' -f $_.Exception.Message) }
    } finally {
        $body = $null
    }

    if ([string]::IsNullOrWhiteSpace([string]$token)) {
        return [pscustomobject]@{ LogonOk = $false; LogoffOk = $false; Message = 'Logon returned an empty token.' }
    }

    try {
        Write-CheckLog -Level Debug -Message ("POST {0}" -f $logoffUri)
        Invoke-RestMethod -Method Post -Uri $logoffUri -Headers @{ Authorization = [string]$token } `
            -ContentType 'application/json' -TimeoutSec $TimeoutSec -ErrorAction Stop | Out-Null
        return [pscustomobject]@{ LogonOk = $true; LogoffOk = $true; Message = 'Logon and logoff worked.' }
    } catch {
        return [pscustomobject]@{ LogonOk = $true; LogoffOk = $false; Message = ('Logon worked. Logoff failed: {0}' -f $_.Exception.Message) }
    } finally {
        $token = $null
    }
}

try {
    $net = (Get-CheckSettings).Network
    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Any -IncludeStandby -IncludeVirtual)
    Write-CheckLog -Level Info -Message ("Testing {0} server name(s)." -f $targets.Count)

    foreach ($t in $targets) {
        $roleSettings = Get-RoleSettings -Role $t.Role
        Write-CheckLog -Level Verbose -Message ("Testing {0} ({1})." -f $t.Host, $t.Role)

        $addresses = Resolve-HostAddress -ComputerName $t.Host
        if (-not $addresses) {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'DNS' -Status Fail -Message 'Name does not resolve.'
            continue
        }
        Add-Finding -Role $t.Role -Target $t.Host -Item 'DNS' -Status Pass -Message ($addresses -join ', ')

        foreach ($port in @($roleSettings.Ports)) {
            if (Test-TcpPort -ComputerName $t.Host -Port ([int]$port) -TimeoutMs $net.TcpTimeoutMs) {
                Add-Finding -Role $t.Role -Target $t.Host -Item ('TCP {0}' -f $port) -Status Pass -Message 'Port accepts connections.'
            } else {
                Add-Finding -Role $t.Role -Target $t.Host -Item ('TCP {0}' -f $port) -Status Fail -Message 'Port does not accept connections.'
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($roleSettings.HealthUrl)) {
            $url = ([string]$roleSettings.HealthUrl).Replace('{host}', $t.Host)
            $timer = [System.Diagnostics.Stopwatch]::StartNew()
            try {
                $response = Invoke-WebRequest -Uri $url -UseBasicParsing -Method Get -TimeoutSec $net.WebTimeoutSec -ErrorAction Stop
                $timer.Stop()
                $ms = [int]$timer.ElapsedMilliseconds
                if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                    if ($ms -gt $net.SlowResponseMs) {
                        Add-Finding -Role $t.Role -Target $t.Host -Item 'Web health' -Status Warn -Message ('HTTP {0} but slow: {1} ms.' -f $response.StatusCode, $ms)
                    } else {
                        Add-Finding -Role $t.Role -Target $t.Host -Item 'Web health' -Status Pass -Message ('HTTP {0} in {1} ms.' -f $response.StatusCode, $ms)
                    }
                } else {
                    Add-Finding -Role $t.Role -Target $t.Host -Item 'Web health' -Status Fail -Message ('HTTP {0}.' -f $response.StatusCode)
                }
            } catch {
                Add-Finding -Role $t.Role -Target $t.Host -Item 'Web health' -Status Fail -Message $_.Exception.Message
            }
        }

        if ($roleSettings.ApiLogon) {
            if ($Simulate) {
                Write-CheckLog -Level Sim -Message ("Would open and close one API session on {0}." -f $t.Host)
                Add-Finding -Role $t.Role -Target $t.Host -Item 'API session' -Status Skipped -Message 'Simulation. No session opened.'
            } elseif ($null -eq $ApiCredential) {
                Add-Finding -Role $t.Role -Target $t.Host -Item 'API session' -Status Skipped -Message 'No -ApiCredential given.'
            } else {
                $api = Test-ApiSession -HostName $t.Host -RoleSettings $roleSettings -Credential $ApiCredential -TimeoutSec $net.WebTimeoutSec
                if ($api.LogonOk -and $api.LogoffOk) {
                    Add-Finding -Role $t.Role -Target $t.Host -Item 'API session' -Status Pass -Message $api.Message
                } elseif ($api.LogonOk) {
                    Add-Finding -Role $t.Role -Target $t.Host -Item 'API session' -Status Warn -Message $api.Message
                } else {
                    Add-Finding -Role $t.Role -Target $t.Host -Item 'API session' -Status Fail -Message $api.Message
                }
            }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
