<# 
.SYNOPSIS
  Windows Server inventory. Single CSV with section headings.

.SECTIONS
  System Identity
  Operating System
  Security & Identity
  Software & Updates
  Networking
  Windows Roles & Features

.OUTPUT
  C:\Temp\ServerInventory-<timestamp>.csv
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# helper functions
function New-DirIfMissing { param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Try-Run { param([scriptblock]$Script,[object]$Default=$null)
  try { & $Script } catch { $Default }
}

function Parse-InstallDate { param($raw)
  if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
  if ($raw -is [datetime]) { return $raw }
  if ($raw -match '^\d{8}$') { return [datetime]::ParseExact($raw,'yyyyMMdd',$null) }
  try { return [datetime]$raw } catch { return $null }
}

function Add-HeadingRow { param([string]$Title)
  [pscustomobject]@{
    Section      = "=== $Title ==="
    Item         = $null
    Name         = $null
    Version      = $null
    Publisher    = $null
    InstalledOn  = $null
    Details      = $null
  }
}

# Output target
$OutRoot = 'C:\Temp'
New-DirIfMissing $OutRoot
$stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$outCsv = Join-Path $OutRoot "ServerInventory-$stamp.csv"

# Master row list (uniform columns for one CSV)
$rows = New-Object System.Collections.Generic.List[object]

##############################################
# System Identity
##############################################
$rows.Add((Add-HeadingRow 'System Identity'))

$cs   = Get-CimInstance -ClassName Win32_ComputerSystem
$bios = Get-CimInstance -ClassName Win32_BIOS
$enc  = Try-Run { Get-CimInstance -ClassName Win32_SystemEnclosure }

$macs = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -ExpandProperty MacAddress
$ipv4 = Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -ne '127.0.0.1' | Select-Object -ExpandProperty IPAddress
$ipv6 = Get-NetIPAddress -AddressFamily IPv6 | Select-Object -ExpandProperty IPAddress

$sysPairs = @(
  @{K='ComputerName';V=$env:COMPUTERNAME}
  @{K='Domain';      V=$cs.Domain}
  @{K='Workgroup';   V=($(if ($cs.PartOfDomain) { $null } else { $cs.Workgroup }))}
  @{K='Manufacturer';V=$cs.Manufacturer}
  @{K='Model';       V=$cs.Model}
  @{K='SerialNumber';V=$bios.SerialNumber}
  @{K='BIOSVersion'; V=$bios.SMBIOSBIOSVersion}
  @{K='AssetTag';    V=(Try-Run { ($enc.SMBIOSAssetTag -join ', ') })}
  @{K='MACAddresses';V=($macs -join '; ')}
  @{K='IPv4';        V=($ipv4 -join '; ')}
  @{K='IPv6';        V=($ipv6 -join '; ')}
)

foreach ($p in $sysPairs) {
  $rows.Add([pscustomobject]@{
    Section     = 'System Identity'
    Item        = $p.K
    Name        = $null
    Version     = $null
    Publisher   = $null
    InstalledOn = $null
    Details     = $p.V
  })
}

##############################################
# Operating System
##############################################
$rows.Add((Add-HeadingRow 'Operating System'))

$os = Get-CimInstance -ClassName Win32_OperatingSystem
$installDate = Try-Run { [Management.ManagementDateTimeConverter]::ToDateTime($os.InstallDate) }
$lastBoot    = Try-Run { [Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime) }
$uptimeDays  = if ($lastBoot) { [math]::Round((New-TimeSpan -Start $lastBoot -End (Get-Date)).TotalDays,2) } else { $null }
$tz          = Try-Run { (Get-TimeZone).Id }
$ntpCfg      = Try-Run { (w32tm /query /configuration) -join ' ' }

$osPairs = @(
  @{K='Caption';     V=$os.Caption}
  @{K='Version';     V=$os.Version}
  @{K='BuildNumber'; V=$os.BuildNumber}
  @{K='InstallDate'; V=$installDate}
  @{K='LastBoot';    V=$lastBoot}
  @{K='UptimeDays';  V=$uptimeDays}
  @{K='TimeZone';    V=$tz}
  @{K='NtpConfig';   V=$ntpCfg}
)

foreach ($p in $osPairs) {
  $rows.Add([pscustomobject]@{
    Section     = 'Operating System'
    Item        = $p.K
    Name        = $null
    Version     = $null
    Publisher   = $null
    InstalledOn = $null
    Details     = $p.V
  })
}

##############################################
# Security & Identity
##############################################
$rows.Add((Add-HeadingRow 'Security & Identity'))

$localAdmins = Try-Run { Get-LocalGroupMember -Group 'Administrators' | Select-Object -ExpandProperty Name }
$rdpRegPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
$nlaRegPath  = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
$rdpEnabled  = Try-Run { -not [bool](Get-ItemProperty -Path $rdpRegPath -Name 'fDenyTSConnections').fDenyTSConnections }
$nlaEnabled  = Try-Run { [bool](Get-ItemProperty -Path $nlaRegPath -Name 'UserAuthentication').UserAuthentication }
$netAccounts = Try-Run { (net accounts) -join ' ' }

# cert summary — defensive
$certs   = Try-Run { Get-ChildItem Cert:\LocalMachine\My }
$certs   = @($certs) | Where-Object { $_ }
$certCnt = ($certs | Measure-Object).Count
$exp30   = ($certs | Where-Object { $_.NotAfter -le (Get-Date).AddDays(30) } | Measure-Object).Count
$exp90   = ($certs | Where-Object { $_.NotAfter -le (Get-Date).AddDays(90) } | Measure-Object).Count
$latest  = if ($certCnt -gt 0) { $certs | Sort-Object NotAfter -Descending | Select-Object -First 1 -ExpandProperty NotAfter } else { $null }

$secPairs = @(
  @{K='LocalAdministrators'; V=($localAdmins -join '; ')}
  @{K='RdpEnabled';          V=$rdpEnabled}
  @{K='NlaEnabled';          V=$nlaEnabled}
  @{K='PasswordPolicy';      V=$netAccounts}
  @{K='CertsTotal';          V=$certCnt}
  @{K='CertsExpiringIn30d';  V=$exp30}
  @{K='CertsExpiringIn90d';  V=$exp90}
  @{K='CertLatestExpiry';    V=$latest}
)

foreach ($p in $secPairs) {
  $rows.Add([pscustomobject]@{
    Section     = 'Security & Identity'
    Item        = $p.K
    Name        = $null
    Version     = $null
    Publisher   = $null
    InstalledOn = $null
    Details     = $p.V
  })
}

# =====================================================================================
# 4) Software & Updates
# =====================================================================================
$rows.Add((Add-HeadingRow 'Software & Updates'))

# Installed Software (defensive property access, no UninstallString)
$regPaths = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$apps = Get-ItemProperty $regPaths -ErrorAction SilentlyContinue |
  ForEach-Object {
    $hasDN = $_.PSObject.Properties.Match('DisplayName').Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($_.DisplayName)
    if (-not $hasDN) { return }

    $dispVer   = if ($_.PSObject.Properties.Match('DisplayVersion').Count) { $_.DisplayVersion } else { $null }
    $publisher = if ($_.PSObject.Properties.Match('Publisher').Count)      { $_.Publisher }      else { $null }
    $install   = if ($_.PSObject.Properties.Match('InstallDate').Count)    { $_.InstallDate }    else { $null }

    [pscustomobject]@{
      Name        = $_.DisplayName
      Version     = $dispVer
      Publisher   = $publisher
      InstalledOn = Parse-InstallDate $install
    }
  } | Sort-Object Name

foreach ($a in $apps) {
  $rows.Add([pscustomobject]@{
    Section     = 'Software & Updates'
    Item        = 'InstalledSoftware'
    Name        = $a.Name
    Version     = $a.Version
    Publisher   = $a.Publisher
    InstalledOn = $a.InstalledOn
    Details     = $null
  })
}

# Windows Updates / Hotfixes
$updates = Get-HotFix | Select-Object HotFixID, Description, InstalledBy, InstalledOn | Sort-Object InstalledOn

foreach ($u in $updates) {
  $rows.Add([pscustomobject]@{
    Section     = 'Software & Updates'
    Item        = 'InstalledUpdate'
    Name        = $u.HotFixID
    Version     = $u.Description
    Publisher   = $u.InstalledBy
    InstalledOn = $u.InstalledOn
    Details     = $null
  })
}

##############################################
# Networking
##############################################
$rows.Add((Add-HeadingRow 'Networking'))

$adapters = Get-NetAdapter | Select-Object Name, InterfaceDescription, Status, LinkSpeed, MacAddress
foreach ($ad in $adapters) {
  $rows.Add([pscustomobject]@{
    Section     = 'Networking'
    Item        = 'Adapter'
    Name        = $ad.Name
    Version     = $null
    Publisher   = $null
    InstalledOn = $null
    Details     = "Desc=$($ad.InterfaceDescription); Status=$($ad.Status); Speed=$($ad.LinkSpeed); MAC=$($ad.MacAddress)"
  })
}

$ips = Get-NetIPAddress | Select-Object InterfaceAlias, AddressFamily, IPAddress, PrefixLength
foreach ($ip in $ips) {
  $rows.Add([pscustomobject]@{
    Section     = 'Networking'
    Item        = 'IP'
    Name        = $ip.InterfaceAlias
    Version     = $ip.AddressFamily
    Publisher   = $null
    InstalledOn = $null
    Details     = "$($ip.IPAddress)/$($ip.PrefixLength)"
  })
}

$dns = Get-DnsClientServerAddress | Select-Object InterfaceAlias, AddressFamily, ServerAddresses
foreach ($d in $dns) {
  $rows.Add([pscustomobject]@{
    Section     = 'Networking'
    Item        = 'DNS'
    Name        = $d.InterfaceAlias
    Version     = $d.AddressFamily
    Publisher   = $null
    InstalledOn = $null
    Details     = ($d.ServerAddresses -join '; ')
  })
}

$routes = Get-NetRoute -DestinationPrefix '0.0.0.0/0','::/0' -ErrorAction SilentlyContinue |
          Select-Object DestinationPrefix, InterfaceAlias, NextHop, RouteMetric
foreach ($r in $routes) {
  $rows.Add([pscustomobject]@{
    Section     = 'Networking'
    Item        = 'DefaultRoute'
    Name        = $r.InterfaceAlias
    Version     = $null
    Publisher   = $null
    InstalledOn = $null
    Details     = "$($r.DestinationPrefix) via $($r.NextHop) metric $($r.RouteMetric)"
  })
}

$fwProf = Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction
foreach ($fp in $fwProf) {
  $rows.Add([pscustomobject]@{
    Section     = 'Networking'
    Item        = 'FirewallProfile'
    Name        = $fp.Name
    Version     = $null
    Publisher   = $null
    InstalledOn = $null
    Details     = "Enabled=$($fp.Enabled); Inbound=$($fp.DefaultInboundAction); Outbound=$($fp.DefaultOutboundAction)"
  })
}

##############################################
# Windows Roles & Features
##############################################
$rows.Add((Add-HeadingRow 'Windows Roles & Features'))

Import-Module ServerManager -ErrorAction SilentlyContinue
$rolesFeatures = Try-Run { 
  Get-WindowsFeature | Where-Object InstallState -eq 'Installed' |
    Select-Object Name, DisplayName, FeatureType
}

foreach ($rf in $rolesFeatures) {
  $rows.Add([pscustomobject]@{
    Section     = 'Windows Roles & Features'
    Item        = $rf.FeatureType
    Name        = $rf.Name
    Version     = $null
    Publisher   = $null
    InstalledOn = $null
    Details     = $rf.DisplayName
  })
}

# -------- write one CSV --------
$rows | Export-Csv -Path $outCsv -NoTypeInformation -Encoding UTF8

Write-Host "Done. Single CSV written to: $outCsv"
