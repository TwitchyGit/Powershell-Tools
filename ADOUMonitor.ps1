<#
.SYNOPSIS
  Monitor OU structural changes across multiple AD domains.

.DESCRIPTION
  For each domain:
    - Queries all OUs and builds a snapshot:
        ObjectGUID
        DistinguishedName
        gPLink
        gPOptions
        ProtectedFromAccidentalDeletion
    - Compares current snapshot with last snapshot for that domain.
    - Detects:
        Added OUs
        Removed OUs
        Renamed OUs (same parent, different RDN)
        Moved OUs (different parent)
        GPO changes ONLY where GPO name contains "CyberArk"
        Accidental deletion protection changes
    - Writes a change report text file.
    - Updates the "latest" snapshot CSV.

  Output via Write-Output only, suitable for Autosys logs.
#>

param(
    [string[]]$Domains,
    [string]$OutputRoot = 'C:\AD_OU_Monitor'
)

if (-not $Domains -or $Domains.Count -eq 0) {
    Write-Output 'ERROR: No domains specified. Use -Domains domain1,domain2'
    exit 1
}

$WarningPreference = 'SilentlyContinue'
$scriptExitCode = 0

function Get-GpoGuidsFromGpLink {
    param(
        [string]$gpLinkString
    )

    if (-not $gpLinkString) { return @() }

    $matches = [regex]::Matches($gpLinkString, '{([0-9a-fA-F-]+)}')
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($m in $matches) {
        $list.Add($m.Groups[1].Value)
    }
    return $list
}

try {
    Import-Module ActiveDirectory -ErrorAction Stop
} catch {
    Write-Output 'ERROR: Failed to import ActiveDirectory module.'
    exit 1
}

try {
    Import-Module GroupPolicy -ErrorAction Stop
} catch {
    Write-Output 'ERROR: Failed to import GroupPolicy module.'
    exit 1
}

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    try {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    } catch {
        Write-Output ("ERROR: Unable to create output root path: {0}" -f $OutputRoot)
        exit 1
    }
}

$now = Get-Date
$nowStamp = $now.ToString('yyyyMMdd_HHmmss')

foreach ($domain in $Domains) {

    if ([string]::IsNullOrWhiteSpace($domain)) { continue }

    $domainTrimmed = $domain.Trim()
    $domainSafe = ($domainTrimmed -replace '[^a-zA-Z0-9_.-]', '_')
    $domainDir = Join-Path $OutputRoot $domainSafe

    if (-not (Test-Path -LiteralPath $domainDir)) {
        try {
            New-Item -ItemType Directory -Path $domainDir -Force | Out-Null
        } catch {
            Write-Output ("ERROR: {0} - Unable to create domain directory: {1}" -f $domainTrimmed, $domainDir)
            $scriptExitCode = 1
            continue
        }
    }

    $latestCsv   = Join-Path $domainDir 'OUs_latest.csv'
    $snapshotCsv = Join-Path $domainDir ("OUs_{0}.csv" -f $nowStamp)
    $reportFile  = Join-Path $domainDir ("OU_Changes_{0}.txt" -f $nowStamp)

    Write-Output ("INFO: Processing domain {0}" -f $domainTrimmed)

    $defaultNC = $null
    try {
        $rootDse = Get-ADRootDSE -Server $domainTrimmed -ErrorAction Stop
        $defaultNC = $rootDse.defaultNamingContext
    } catch {
        Write-Output ("ERROR: {0} - Failed to query RootDSE." -f $domainTrimmed)
        $scriptExitCode = 1
        continue
    }

    if (-not $defaultNC) {
        Write-Output ("ERROR: {0} - defaultNamingContext not returned." -f $domainTrimmed)
        $scriptExitCode = 1
        continue
    }

    $currentSnapshot = @()
    try {
        $ous = Get-ADOrganizationalUnit -Server $domainTrimmed -SearchBase $defaultNC -Filter * -SearchScope Subtree -Properties gPLink,gPOptions,ProtectedFromAccidentalDeletion -ErrorAction Stop
    } catch {
        Write-Output ("ERROR: {0} - Failed to query OUs." -f $domainTrimmed)
        $scriptExitCode = 1
        continue
    }

    foreach ($ou in $ous) {
        $obj = [PSCustomObject]@{
            ObjectGUID                      = $ou.ObjectGUID.ToString()
            DistinguishedName               = $ou.DistinguishedName
            gPLink                          = $ou.gPLink
            gPOptions                       = $ou.gPOptions
            ProtectedFromAccidentalDeletion = [bool]($ou.ProtectedFromAccidentalDeletion)
        }
        $currentSnapshot += $obj
    }

    try {
        $currentSnapshot |
            Sort-Object ObjectGUID |
            Export-Csv -Path $snapshotCsv -NoTypeInformation -Encoding UTF8
    } catch {
        Write-Output ("ERROR: {0} - Failed to write snapshot CSV: {1}" -f $domainTrimmed, $snapshotCsv)
        $scriptExitCode = 1
        continue
    }

    $previousSnapshot = @()
    if (Test-Path -LiteralPath $latestCsv) {
        try {
            $previousSnapshot = Import-Csv -Path $latestCsv
        } catch {
            Write-Output ("ERROR: {0} - Failed to read previous snapshot: {1}" -f $domainTrimmed, $latestCsv)
            $scriptExitCode = 1
            $previousSnapshot = @()
        }
    }

    $prevByGuid = @{}
    foreach ($p in $previousSnapshot) {
        if (-not $prevByGuid.ContainsKey($p.ObjectGUID)) {
            $prevByGuid[$p.ObjectGUID] = $p
        }
    }

    $currByGuid = @{}
    foreach ($c in $currentSnapshot) {
        if (-not $currByGuid.ContainsKey($c.ObjectGUID)) {
            $currByGuid[$c.ObjectGUID] = $c
        }
    }

    $prevGuids = $prevByGuid.Keys
    $currGuids = $currByGuid.Keys

    $addedGuids   = @($currGuids | Where-Object { -not $prevGuids -contains $_ })
    $removedGuids = @($prevGuids | Where-Object { -not $currGuids -contains $_ })

    $renamed     = New-Object System.Collections.Generic.List[object]
    $moved       = New-Object System.Collections.Generic.List[object]
    $gpoChanged  = New-Object System.Collections.Generic.List[object]
    $protChanged = New-Object System.Collections.Generic.List[object]

    foreach ($guid in $currGuids) {

        if (-not $prevByGuid.ContainsKey($guid)) { continue }

        $prev = $prevByGuid[$guid]
        $curr = $currByGuid[$guid]

        $prevDN = $prev.DistinguishedName
        $currDN = $curr.DistinguishedName

        if ($prevDN -ne $currDN) {
            $prevParts = $prevDN -split '(?<!\\),'
            $currParts = $currDN -split '(?<!\\),'

            $prevRdn = if ($prevParts.Count -gt 0) { $prevParts[0] } else { $null }
            $currRdn = if ($currParts.Count -gt 0) { $currParts[0] } else { $null }

            $prevParent = if ($prevParts.Count -gt 1) { ($prevParts[1..($prevParts.Count - 1)] -join ',') } else { '' }
            $currParent = if ($currParts.Count -gt 1) { ($currParts[1..($currParts.Count - 1)] -join ',') } else { '' }

            if ($prevParent -ne $currParent -and $prevRdn -eq $currRdn) {
                $moved.Add([PSCustomObject]@{
                    ObjectGUID = $guid
                    OldDN      = $prevDN
                    NewDN      = $currDN
                })
            } elseif ($prevRdn -ne $currRdn -and $prevParent -eq $currParent) {
                $renamed.Add([PSCustomObject]@{
                    ObjectGUID = $guid
                    OldDN      = $prevDN
                    NewDN      = $currDN
                })
            } else {
                $moved.Add([PSCustomObject]@{
                    ObjectGUID = $guid
                    OldDN      = $prevDN
                    NewDN      = $currDN
                })
                $renamed.Add([PSCustomObject]@{
                    ObjectGUID = $guid
                    OldDN      = $prevDN
                    NewDN      = $currDN
                })
            }
        }

        $prevGpLink = $prev.gPLink
        $currGpLink = $curr.gPLink
        $prevGpOpt  = $prev.gPOptions
        $currGpOpt  = $curr.gPOptions

        if ($prevGpLink -ne $currGpLink -or $prevGpOpt -ne $currGpOpt) {

            $prevGuidsGpo = Get-GpoGuidsFromGpLink -gpLinkString $prevGpLink
            $currGuidsGpo = Get-GpoGuidsFromGpLink -gpLinkString $currGpLink

            $diffGuids = @()
            $diffGuids += ($currGuidsGpo | Where-Object { $_ -notin $prevGuidsGpo })
            $diffGuids += ($prevGuidsGpo | Where-Object { $_ -notin $currGuidsGpo })

            $changedCyberArk = New-Object System.Collections.Generic.List[object]

            foreach ($gGuid in $diffGuids) {
                try {
                    $gpo = Get-GPO -Guid $gGuid -Domain $domainTrimmed -ErrorAction Stop
                    if ($gpo.DisplayName -match 'CyberArk') {
                        $changedCyberArk.Add([PSCustomObject]@{
                            GpoGuid = $gGuid
                            GpoName = $gpo.DisplayName
                        })
                    }
                } catch {
                    # ignore GPO resolution issues
                }
            }

            if ($changedCyberArk.Count -gt 0) {
                foreach ($cg in $changedCyberArk) {
                    $gpoChanged.Add([PSCustomObject]@{
                        ObjectGUID        = $guid
                        DistinguishedName = $currDN
                        GpoGuid           = $cg.GpoGuid
                        GpoName           = $cg.GpoName
                        OldgPLink         = $prevGpLink
                        NewgPLink         = $currGpLink
                        OldgPOptions      = $prevGpOpt
                        NewgPOptions      = $currGpOpt
                    })
                }
            }
        }

        $prevProt = [string]$prev.ProtectedFromAccidentalDeletion
        $currProt = [string]$curr.ProtectedFromAccidentalDeletion

        if ($prevProt -ne $currProt) {
            $protChanged.Add([PSCustomObject]@{
                ObjectGUID        = $guid
                DistinguishedName = $currDN
                OldProtected      = $prevProt
                NewProtected      = $currProt
            })
        }
    }

    $reportLines = New-Object System.Collections.Generic.List[string]
    $reportLines.Add(("Domain: {0}" -f $domainTrimmed))
    $reportLines.Add(("RunTime: {0}" -f $now.ToString('yyyy-MM-dd HH:mm:ss')))
    $reportLines.Add("")

    $changesFound = $false

    $reportLines.Add("Added OUs (new objects):")
    if ($addedGuids.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($guid in $addedGuids) {
            $ou = $currByGuid[$guid]
            $reportLines.Add(("  + {0}  GUID={1}" -f $ou.DistinguishedName, $ou.ObjectGUID))
        }
    }

    $reportLines.Add("")
    $reportLines.Add("Removed OUs (missing objects):")
    if ($removedGuids.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($guid in $removedGuids) {
            $ou = $prevByGuid[$guid]
            $reportLines.Add(("  - {0}  GUID={1}" -f $ou.DistinguishedName, $ou.ObjectGUID))
        }
    }

    $reportLines.Add("")
    $reportLines.Add("Renamed OUs (same parent, different RDN):")
    if ($renamed.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($r in $renamed) {
            $reportLines.Add(("  REN GUID={0}" -f $r.ObjectGUID))
            $reportLines.Add(("      Old: {0}" -f $r.OldDN))
            $reportLines.Add(("      New: {0}" -f $r.NewDN))
        }
    }

    $reportLines.Add("")
    $reportLines.Add("Moved OUs (different parent):")
    if ($moved.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($m in $moved) {
            $reportLines.Add(("  MOV GUID={0}" -f $m.ObjectGUID))
            $reportLines.Add(("      Old: {0}" -f $m.OldDN))
            $reportLines.Add(("      New: {0}" -f $m.NewDN))
        }
    }

    $reportLines.Add("")
    $reportLines.Add("CyberArk GPO changes (gPLink / gPOptions):")
    if ($gpoChanged.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($g in $gpoChanged) {
            $reportLines.Add(("  GPO GUID={0}" -f $g.GpoGuid))
            $reportLines.Add(("      Name: {0}" -f $g.GpoName))
            $reportLines.Add(("      OU DN: {0}" -f $g.DistinguishedName))
            $reportLines.Add(("      Old gPLink: {0}" -f $g.OldgPLink))
            $reportLines.Add(("      New gPLink: {0}" -f $g.NewgPLink))
            $reportLines.Add(("      Old gPOptions: {0}" -f $g.OldgPOptions))
            $reportLines.Add(("      New gPOptions: {0}" -f $g.NewgPOptions))
        }
    }

    $reportLines.Add("")
    $reportLines.Add("Accidental deletion protection changes:")
    if ($protChanged.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($p in $protChanged) {
            $reportLines.Add(("  PROT GUID={0}" -f $p.ObjectGUID))
            $reportLines.Add(("      DN: {0}" -f $p.DistinguishedName))
            $reportLines.Add(("      Old Protected: {0}" -f $p.OldProtected))
            $reportLines.Add(("      New Protected: {0}" -f $p.NewProtected))
        }
    }

    if (-not (Test-Path -LiteralPath $latestCsv) -and $currentSnapshot.Count -eq 0) {
        $reportLines.Add("")
        $reportLines.Add("Note: first run for this domain and no OUs returned.")
    } elseif (-not (Test-Path -LiteralPath $latestCsv)) {
        $reportLines.Add("")
        $reportLines.Add("Note: first run for this domain. All OUs will appear as baseline only.")
    }

    try {
        $reportLines | Out-File -FilePath $reportFile -Encoding UTF8
    } catch {
        Write-Output ("ERROR: {0} - Failed to write report file: {1}" -f $domainTrimmed, $reportFile)
        $scriptExitCode = 1
    }

    try {
        Move-Item -LiteralPath $snapshotCsv -Destination $latestCsv -Force
    } catch {
        Write-Output ("ERROR: {0} - Failed to update latest snapshot CSV: {1}" -f $domainTrimmed, $latestCsv)
        $scriptExitCode = 1
    }

    if (-not $changesFound) {
        Write-Output ("INFO: {0} - No OU structural changes detected." -f $domainTrimmed)
    } else {
        Write-Output ("INFO: {0} - OU structural changes detected. Report: {1}" -f $domainTrimmed, $reportFile)
    }
}

exit $scriptExitCode
