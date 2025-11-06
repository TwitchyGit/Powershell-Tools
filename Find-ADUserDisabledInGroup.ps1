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

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)]
  [string]$Group,
  [string]$Server,
  [System.Management.Automation.PSCredential]$Credential,
  [string]$OutFile,
  [switch]$CountOnly,
  [switch]$Quiet
)

# be strict and stop on errors so exit code 2 is reliable
$ErrorActionPreference = 'Stop'

# Import AD
try {
  Import-Module ActiveDirectory -ErrorAction Stop
}
catch {
  Write-Error "mod import fail. $($_.Exception.Message)"
  exit 2
}

# Resolve group
try {
  $grpParams = @{Identity=$Group}
  if ($Server)     { $grpParams.Server     = $Server }
  if ($Credential) { $grpParams.Credential = $Credential }

  $groupObj = Get-ADGroup @grpParams -Properties distinguishedName
  $dn = $groupObj.DistinguishedName
}
catch {
  Write-Error "group lookup fail. $($_.Exception.Message)"
  exit 2
}

# Get users
try {
  $usrParams = @{
    LDAPFilter="(memberOf:1.2.840.113556.1.4.1941:=$dn)"
    Properties=@('Enabled','samAccountName','displayName','userPrincipalName','distinguishedName')
  }
  if ($Server)     { $usrParams.Server     = $Server }
  if ($Credential) { $usrParams.Credential = $Credential }

  $users = Get-ADUser @usrParams
}
catch {
  Write-Error "user query fail. $($_.Exception.Message)"
  exit 2
}

# Filter and output
try {
  $disabled = $users | Where-Object { $_.Enabled -eq $false } |
    Select-Object samAccountName,displayName,userPrincipalName,distinguishedName,Enabled

  $count = ($disabled | Measure-Object).Count

  if (-not $Quiet) {
    if ($CountOnly) {  $count }
    elseif ($OutFile) {
      $disabled | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutFile
    }
    else { $disabled }
  }

  if ($count -gt 0) { exit 1 } else { exit 0 }
}
catch {
  Write-Error "output fail. $($_.Exception.Message)"
  exit 2
}
