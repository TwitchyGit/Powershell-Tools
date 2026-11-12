<#
.SYNOPSIS
    Tests the expiry dates of certificates in the machine certificate stores.

.DESCRIPTION
    Stores and limits come from the Certificates section of the settings.
    A certificate fails if it expires in FailDays or less (or has already expired).
    A certificate warns if it expires in WarnDays or less.
    Certificates that expired more than IgnoreExpiredOlderThanDays ago are ignored.
    Subjects and thumbprints in the ignore lists are skipped.

    This check only reads data. Simulation only stops the report files.

.PARAMETER Role
    Roles to test. Default is all Windows roles.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER Simulate
    Makes no changes. No report files are written.

.EXAMPLE
    .\Check-CertificateExpiry.ps1 -Verbose
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

$ctx = Start-Check -Name 'CertificateExpiry' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$probe = {
    param([string[]]$Stores)
    foreach ($store in $Stores) {
        Get-ChildItem -Path ('Cert:\LocalMachine\{0}' -f $store) -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Store         = $store
                Subject       = [string]$_.Subject
                Thumbprint    = [string]$_.Thumbprint
                NotAfter      = [datetime]$_.NotAfter
                HasPrivateKey = [bool]$_.HasPrivateKey
            }
        }
    }
}

try {
    $cfg = (Get-CheckSettings).Certificates
    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Testing certificates on {0} server(s)." -f $targets.Count)
    $now = Get-Date

    foreach ($t in $targets) {
        try {
            $certs = @(Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $probe -ArgumentList @(, [string[]]@($cfg.Stores)) -Credential $RemoteCredential)
        } catch {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'Certificate query' -Status Error -Message $_.Exception.Message
            continue
        }

        $tested = 0
        $problems = 0
        foreach ($cert in $certs) {
            if ($cfg.OnlyWithPrivateKey -and -not $cert.HasPrivateKey) { continue }
            if (Test-AnyLike -Value $cert.Subject -Pattern @($cfg.IgnoreSubjects)) { continue }
            if ($cert.Thumbprint -in @($cfg.IgnoreThumbprints)) { continue }

            $days = [math]::Floor(($cert.NotAfter - $now).TotalDays)
            if ($days -lt (-1 * $cfg.IgnoreExpiredOlderThanDays)) { continue }

            $tested++
            $item = '{0}: {1}' -f $cert.Store, $cert.Subject
            $text = 'Expires {0:yyyy-MM-dd} ({1} day(s)). Thumbprint {2}.' -f $cert.NotAfter, $days, $cert.Thumbprint
            if ($days -le $cfg.FailDays) {
                $problems++
                Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Fail -Message $text
            } elseif ($days -le $cfg.WarnDays) {
                $problems++
                Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Warn -Message $text
            } else {
                Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Pass -Message $text
            }
        }

        if ($tested -eq 0) {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'Certificates' -Status Info -Message 'No certificates matched the settings.'
        } else {
            Write-CheckLog -Level Verbose -Message ("{0}: {1} certificate(s) tested. {2} need attention." -f $t.Host, $tested, $problems)
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
