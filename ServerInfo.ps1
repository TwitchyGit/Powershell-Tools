<# 
.SYNOPSIS
  Windows Server quick inventory (PS 5.1 compatible)

.OUTPUTS
  C:\Temp\ServerInventory-<timestamp>.json        # full structured report
  C:\Temp\InstalledSoftware-<timestamp>.csv
  C:\Temp\InstalledUpdates-<timestamp>.csv
  C:\Temp\InstalledRolesFeatures-<timestamp>.csv
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#--- helpers ---------------------------------------------------------------

function New-DirIfMissing {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Parse-InstallDate {
    param($raw)
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    if ($raw -is [datetime]) { return $raw }
    # common registry format is yyyyMMdd
    if ($raw -match '^\d{8}$') {
        return [datetime]::ParseExact($raw,'yyyyMMdd',$null)
    }
    # try general cast as fallback
    try { return [datetime]$raw } catch { return $null }
}

function Try-Run {
    param([scriptblock]$Script, [object]$Default=$null)
    try { & $Script } catch { $Default }
}

#--- output file roots -----------------------------------------------------

$OutRoot = 'C:\Temp'
New-DirIfMissing $OutRoot
$stamp  = (Get-Date).ToString('yyyyMMdd-HHmmss')
$jsonOut = Join-Path $OutRoot "ServerInventory-$stamp.json"
$csvApps = Join-Path $OutRoot "InstalledSoftware-$stamp.csv"
$csvHfx  = Join-Path $OutRoot "InstalledUpdates-$stamp.csv"
$csvFeat = Join-Path $OutRoot "InstalledRolesFeatures-$stamp.csv"

#--- System Identity ----------------------------------------------------

$cs   = Get-CimInstance -ClassName Win32_ComputerSystem
$bios = Get-CimInstance -ClassName Win32_BIOS
$enc  = Try-Run { Get-CimInstance -ClassName Win32_SystemEnclosure } # for AssetTag, may be null

$systemIdentity = [pscustomobject]@{
    ComputerName = $env:COMPUTERNAME
    Domain       = $cs.Domain
    Workgroup    = if ($cs.PartOfDomain) { $null } else { $cs.Workgroup }
    Manufacturer = $cs.Manufacturer
    Model        = $cs.Model
    SerialNumber = $bios.SerialNumber
    BIOSVersion  = ($bios.SMBIOSBIOSVersion)
    BIOSRelease  = Try-Run { [datetime]::ParseExact(($bios.ReleaseDate),'yyyyMMddHHmmss.fffffff+000',$null) }
    AssetTag     = Try-Run { ($enc.SMBIOSAssetTag -join ', ') }
    MACAddresses = (Get-NetAdapter | Where-Object {$_.Status -eq 'Up'} | Select-Object -ExpandProperty MacAddress)
    IPv4         = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -ne '127.0.0.1'} | Select-Object -ExpandProperty IPAddress)
    IPv6         = (Get-NetIPAddress -AddressFamily IPv6 | Select-Object -ExpandProperty IPAddress)
}

#--- Operating System ---------------------------------------------------

$os = Get-CimInstance -ClassName Win32_OperatingSystem
$installDate = Try-Run { [Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate) }
$lastBoot    = Try-Run { [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime) }
$uptimeDays  = if ($lastBoot) { [math]::Round((New-TimeSpan -Start $lastBoot -End (Get-Date)).TotalDays,2) } else { $null }

$tz = Try-Run { Get-TimeZone }
$ntpConfig = Try-Run { (w32tm /query /configuration) -join "`n" }

$operatingSystem = [pscustomobject]@{
    Caption        = $os.Caption
    Version        = $os.Version
    BuildNumber    = $os.BuildNumber
    InstallDate    = $installDate
    LastBoot       = $lastBoot
    UptimeDays     = $uptimeDays
    TimeZone       = $tz.Id
    NtpConfigText  = $ntpConfig
}

#--- Security & Identity -----------------------------------------------

# Local Administrators (works on member servers)
$localAdmins = Try-Run { Get-LocalGroupMember -Group 'Administrators' | Select-Object Name, ObjectClass }

# RDP & NLA via registry (no RSAT dependency)
$rdpRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$nlaRegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
$rdpEnabled = Try-Run { -not [bool](Get-ItemProperty -Path $rdpRegPath -Name 'fDenyTSConnections').fDenyTSConnections }
$nlaEnabled = Try-Run { [bool](Get-ItemProperty -Path $nlaRegPath -Name 'UserAuthentication').UserAuthentication }

# Password policy snapshot (simple)
$netAccounts = Try-Run { (net accounts) -join "`n" }

# Certificates (LocalMachine\My) — summary only to avoid huge output
$certs = Try-Run { @(Get-ChildItem Cert:\LocalMachine\My) }

$certSummary = if ($certs -and $certs.Count -gt 0) {
    [pscustomobject]@{
        Total         = $certs.Count
        ExpiringIn30d = ($certs | Where-Object { $_.NotAfter -le (Get-Date).AddDays(30) }).Count
        ExpiringIn90d = ($certs | Where-Object { $_.NotAfter -le (Get-Date).AddDays(90) }).Count
        LatestExpiry  = ($certs | Sort-Object NotAfter -Descending | Select-Object -First 1 -ExpandProperty NotAfter)
    }
} else { $null }

$securityIdentity = [pscustomobject]@{
    LocalAdministrators = $localAdmins
    RdpEnabled          = $rdpEnabled
    NlaEnabled          = $nlaEnabled
    PasswordPolicyText  = $netAccounts
    CertSummary         = $certSummary
}

#--- Software & Updates -------------------------------------------------

# Installed software from both 64/32-bit uninstall keys with proper InstalledOn
$regPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$apps = Get-ItemProperty $regPaths -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName } |
    ForEach-Object {
        [pscustomobject]@{
            Name            = $_.DisplayName
            Version         = $_.DisplayVersion
            Publisher       = $_.Publisher
            InstalledOn     = Parse-InstallDate $_.InstallDate
            UninstallString = $_.UninstallString
        }
    } | Sort-Object Name

$updates = Get-HotFix | Select-Object @{n='Name';e={$_.HotFixID}},
                                  @{n='Description';e={$_.Description}},
                                  @{n='InstalledBy';e={$_.InstalledBy}},
                                  @{n='InstalledOn';e={$_.InstalledOn}} |
           Sort-Object InstalledOn

#--- Networking ---------------------------------------------------------

$adapters = Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress
$ips      = Get-NetIPAddress | Select-Object InterfaceAlias, AddressFamily, IPAddress, PrefixLength
$dns      = Get-DnsClientServerAddress | Select-Object InterfaceAlias, AddressFamily, ServerAddresses
$routes   = Get-NetRoute -DestinationPrefix '0.0.0.0/0','::/0' -ErrorAction SilentlyContinue |
            Select-Object DestinationPrefix, InterfaceAlias, NextHop, RouteMetric
$fwProf   = Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
$listens  = Try-Run { Get-NetTCPConnection -State Listen | Select-Object LocalAddress, LocalPort, OwningProcess }

$networking = [pscustomobject]@{
    Adapters        = $adapters
    IPAddresses     = $ips
    DnsServers      = $dns
    DefaultRoutes   = $routes
    FirewallProfile = $fwProf
    ListeningTcp    = $listens
}

#--- Windows Roles & Features ------------------------------------------

Import-Module ServerManager -ErrorAction SilentlyContinue
$rolesFeatures = Try-Run { 
    Get-WindowsFeature | Where-Object {$_.InstallState -eq 'Installed'} |
        Select-Object Name, DisplayName, InstallState, FeatureType
}

#--- assemble master report ------------------------------------------------

$report = [pscustomobject]@{
    CollectedAtUTC    = (Get-Date).ToUniversalTime()
    SystemIdentity    = $systemIdentity
    OperatingSystem   = $operatingSystem
    SecurityIdentity  = $securityIdentity
    Software          = $apps
    Updates           = $updates
    Networking        = $networking
    RolesAndFeatures  = $rolesFeatures
}

#--- write outputs ---------------------------------------------------------

# JSON (full report)
$report | ConvertTo-Json -Depth 6 | Out-File -FilePath $jsonOut -Encoding UTF8

# CSVs for common slices
$apps        | Export-Csv $csvApps -NoTypeInformation -Encoding UTF8
$updates     | Export-Csv $csvHfx  -NoTypeInformation -Encoding UTF8
$rolesFeatures | Export-Csv $csvFeat -NoTypeInformation -Encoding UTF8

Write-Host "Inventory complete."
Write-Host "Report: $jsonOut"
Write-Host "Apps:   $csvApps"
Write-Host "Updates:$csvHfx"
Write-Host "Roles:  $csvFeat"
