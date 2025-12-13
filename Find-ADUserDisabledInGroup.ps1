# Usage
# .\Find-ADUserDisabledInGroup.ps1 -Group "ADGroupName"
# .\Find-ADUserDisabledInGroup.ps1 -Group "ADGroupName" -CountOnly
# .\Find-ADUserDisabledInGroup.ps1 -Group "ADGroupName" -OutFile "disabled_finance.csv"
# $cred = Get-Credential
# .\Find-ADUserDisabledInGroup.ps1 -Group "CN=ADGroupName,OU=Groups,DC=corp,DC=nom" -Server domaincontroller1.corp.nom -Credential $cred

<# 
.SYNOPSIS
  Find disabled users in (nested) AD group membership

.PARAMETER Group
  Group name, samAccountName, or DN

.PARAMETER Server
  Optional DC to target

.PARAMETER Credential
  Optional PSCredential

.PARAMETER OutFile
  Optional CSV path. If omitted, writes objects to stdout

.PARAMETER CountOnly
  Only output the count of disabled users (stdout), set exit code

.PARAMETER Quiet
  Suppress data output. Exit code reflects result

.RETURNS
  Stdout: objects or count (unless -Quiet)
  Exit codes: 0=none disabled, 1=disabled present, 2=error
#>

<# Scan multiple domains and groups from Configuration.psm1
Requires: ActiveDirectory module, PS 5.0

Configuration.psm1 must expose:
  $ConfADDomains = @('corp.local','emea.local',...)
  $ConfADGroups  = @('Finance Team','CN=HR,OU=Groups,DC=corp,DC=local',...)

Exit codes:
  0 = no disabled users found
  1 = one or more disabled users found
  2 = error
#>

[CmdletBinding()]
param(
  [System.Management.Automation.PSCredential]$Credential,
  [string]$OutFile,
  [switch]$CountOnly,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

try {
  Import-Module ActiveDirectory -Force -ErrorAction Stop
  Import-Module -Name Configuration.psm1 -ErrorAction Stop -Force
} catch {
  Write-Output "ERROR: config module load failed. $($_.Exception.Message)"
  exit 2
}

# read config
try {
  if (-not $script:ConfADDomains -or -not $script:ConfADGroups) { 
    throw "ConfADDomains or ConfADGroups not found in the config module" 
  }
  $Domains = @($script:ConfADDomains) | Where-Object { $_ } | Select-Object -Unique
  $Groups  = @($script:ConfADGroups)  | Where-Object { $_ }
  if ($Domains.Count -eq 0 -or $Groups.Count -eq 0) { 
    throw "empty ConfADDomains or ConfADGroups" 
  }
} catch {
  Write-Output "ERROR: Config read failed. $($_.Exception.Message)"
  exit 2
}

# helper: escape LDAP special characters
function Escape-LDAPFilter {
  param([string]$Value)
  $Value = $Value -replace '\\', '\5c'
  $Value = $Value -replace '\*', '\2a'
  $Value = $Value -replace '\(', '\28'
  $Value = $Value -replace '\)', '\29'
  $Value = $Value -replace '\x00', '\00'
  return $Value
}

# helper: resolve a group DN within a specific domain
function Resolve-GroupDN {
  param([string]$Group,[string]$Domain,[System.Management.Automation.PSCredential]$Cred)
  $common = @{ Server = $Domain }
  if ($Cred) { $common.Credential = $Cred }

  # try direct identity first
  try {
    $g = Get-ADGroup @common -Identity $Group -Properties distinguishedName
    if ($g -and $g.DistinguishedName) { return $g.DistinguishedName }
  } catch { }

  # fallback: search by samAccountName or CN under domain naming context
  try {
    $base = (Get-ADDomain @common).DistinguishedName
    $escaped = Escape-LDAPFilter -Value $Group
    $flt = "(|(samAccountName=$escaped)(cn=$escaped))"
    $g2 = Get-ADGroup @common -LDAPFilter $flt -SearchBase $base -SearchScope Subtree -Properties distinguishedName |
          Select-Object -First 1
    if ($g2 -and $g2.DistinguishedName) { return $g2.DistinguishedName }
  } catch { }

  return $null
}

# 3) validate output path if specified
if ($OutFile) {
  try {
    $parentPath = Split-Path -Path $OutFile -Parent
    if ($parentPath -and -not (Test-Path -Path $parentPath -PathType Container)) {
      Write-Error "output directory does not exist: $parentPath"
      exit 2
    }
  }
  catch { Write-Output "ERROR: invalid output path. $($_.Exception.Message)"; exit 2 }
}

# 4) validate groups per domain
$validPairs = New-Object System.Collections.Generic.List[object]
$invalid    = New-Object System.Collections.Generic.List[string]

foreach ($d in $Domains) {
  foreach ($g in $Groups) {
    try {
      $dn = Resolve-GroupDN -Group $g -Domain $d -Cred $Credential
      if ($dn) {
        $validPairs.Add([pscustomobject]@{ Domain=$d; GroupInput=$g; GroupDN=$dn })
      } else {
        $invalid.Add("domain=$d group=$g")
      }
    }
    catch { $invalid.Add("domain=$d group=$g error=$($_.Exception.Message)") }
  }
}

if ($validPairs.Count -eq 0) {
  if ($invalid.Count -gt 0) { Write-Error ("no valid groups found. invalid: " + ($invalid -join '; ')) }
  else { Write-Error "no valid groups found" }
  exit 2
}

# 5) query users for each valid pair and aggregate disabled
$results = New-Object System.Collections.Generic.List[object]
$queryErrors = New-Object System.Collections.Generic.List[string]

foreach ($pair in $validPairs) {
  try {
    $params = @{
      Server     = $pair.Domain
      LDAPFilter = "(&(objectClass=user)(objectCategory=person)(memberOf:1.2.840.113556.1.4.1941:=$($pair.GroupDN)))"
      Properties = @('Enabled','samAccountName','displayName','userPrincipalName','distinguishedName')
    }
    if ($Credential) { $params.Credential = $Credential }

    $users = Get-ADUser @params

    $disabled = $users | Where-Object { $_.Enabled -eq $false } |
      Select-Object @{n='Domain';e={$pair.Domain}},
                    @{n='Group'; e={$pair.GroupInput}},
                    samAccountName, displayName, userPrincipalName, distinguishedName, Enabled

    foreach ($u in $disabled) { $results.Add($u) }
  }
  catch {
    $errMsg = "query failed for domain=$($pair.Domain) group=$($pair.GroupInput). $($_.Exception.Message)"
    $queryErrors.Add($errMsg)
    Write-Warning $errMsg
  }
}

# warn if all queries failed
if ($queryErrors.Count -eq $validPairs.Count) {
  Write-Output "ERROR: all queries failed. errors: $($queryErrors -join '; ')"
  exit 2
}

# 6) deduplicate results by distinguishedName
$uniqueResults = $results | Sort-Object -Property distinguishedName -Unique

# 7) output and exit code
try {
  $count = $uniqueResults.Count
  if (-not $Quiet) {
    if ($CountOnly) {
      $count
    } elseif ($OutFile) {
      $uniqueResults | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutFile
    } else {
      $uniqueResults
    }
  }
  if ($count -gt 0) { exit 1 } else { exit 0 }
}
catch {
  Write-Output "ERROR: output failed. $($_.Exception.Message)"
  exit 2
}

