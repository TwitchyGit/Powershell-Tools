<#
.SYNOPSIS
    Monitors Active Directory Organizational Unit (OU) structural changes across multiple domains.

.DESCRIPTION
    This script detects and reports structural changes to OUs in Active Directory domains by:
    - Creating snapshots of all OUs with their properties (GUID, DN, GPO links, protection status)
    - Comparing current snapshot with the previous snapshot for each domain
    - Detecting: Added OUs, Removed OUs, Renamed OUs, Moved OUs, CyberArk GPO changes, Protection changes
    - Writing detailed change reports to text files
    - Maintaining rolling "latest" snapshot CSV files for each domain
    
    Requires: Install-WindowsFeature GPMC (Group Policy Management Console)
    
    Output is via Write-Output only, suitable for Autosys or scheduled task logs.

.PARAMETER Domains
    Array of domain names to monitor (NetBIOS or DNS names).

.PARAMETER OutputRoot
    Root directory path where domain-specific folders and reports will be stored.
    Defaults to C:\AD_OU_Monitor

.EXAMPLE
    .\AD_OU_Monitor.ps1 -Domains "contoso.com","fabrikam.com" -OutputRoot "D:\Monitoring\AD_OUs"

.NOTES
    Requires: Active Directory and Group Policy PowerShell modules
    Author: AD OU Monitor
    Version: 1.0
    
    The script only reports GPO changes where the GPO name contains "CyberArk"
#>

param(
    [string[]]$Domains,
    [string]$OutputRoot = 'C:\AD_OU_Monitor'
)

# Validate required parameters
if (-not $Domains -or $Domains.Count -eq 0) {
    Write-Output 'ERROR: No domains specified. Use -Domains domain1,domain2'
    exit 1
}

# Suppress warnings to keep output clean for logs
$WarningPreference = 'SilentlyContinue'
$scriptExitCode = 0

#region Helper Functions

function Get-GpoGuidsFromGpLink {
    <#
    .SYNOPSIS
        Extracts GPO GUIDs from a gPLink attribute string.
    
    .DESCRIPTION
        The gPLink attribute contains LDAP paths with embedded GUIDs.
        This function uses regex to extract all GUID values.
        Example gPLink: [LDAP://cn={GUID1},cn=policies,...;0][LDAP://cn={GUID2},...;0]
    #>
    param(
        [string]$gpLinkString
    )

    if (-not $gpLinkString) { return @() }

    # Extract all GUIDs using regex pattern for GUID format
    $matches = [regex]::Matches($gpLinkString, '{([0-9a-fA-F-]+)}')
    $list = New-Object System.Collections.Generic.List[string]
    foreach ($m in $matches) {
        $list.Add($m.Groups[1].Value)
    }
    return $list
}
#endregion

#region Module Import
# Import only required cmdlets from Active Directory module
try {
    Import-Module ActiveDirectory -Cmdlet Get-ADRootDSE, Get-ADOrganizationalUnit -ErrorAction Stop
} catch {
    Write-Output 'ERROR: Failed to import ActiveDirectory module.'
    exit 1
}

# Import only required cmdlet from Group Policy module
try {
    Import-Module GroupPolicy -Cmdlet Get-GPO -ErrorAction Stop
} catch {
    Write-Output 'ERROR: Failed to import GroupPolicy module.'
    exit 1
}
#endregion

#region Output Directory Setup
# Ensure root output directory exists
if (-not (Test-Path -LiteralPath $OutputRoot)) {
    try {
        New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
    } catch {
        Write-Output "ERROR: Unable to create output root path: $OutputRoot"
        exit 1
    }
}
#endregion

#region Main Processing
# Capture current timestamp for this monitoring run
$now = Get-Date
$nowStamp = $now.ToString('yyyyMMdd_HHmmss')

# Process each domain independently
foreach ($domain in $Domains) {

    # Skip empty domain entries
    if ([string]::IsNullOrWhiteSpace($domain)) { continue }

    # Prepare domain-specific paths
    $domainTrimmed = $domain.Trim()
    $domainSafe = ($domainTrimmed -replace '[^a-zA-Z0-9_.-]', '_')  # Sanitize for filesystem
    $domainDir = Join-Path $OutputRoot $domainSafe

    # Create domain-specific output directory if needed
    if (-not (Test-Path -LiteralPath $domainDir)) {
        try {
            New-Item -ItemType Directory -Path $domainDir -Force | Out-Null
        } catch {
            Write-Output "ERROR: $domainTrimmed - Unable to create domain directory: $domainDir"
            $scriptExitCode = 1
            continue
        }
    }

    # Define file paths for this domain
    $latestCsv   = Join-Path $domainDir 'OUs_latest.csv'                      # Rolling latest snapshot
    $snapshotCsv = Join-Path $domainDir "OUs_$nowStamp.csv"                   # Timestamped snapshot
    $reportFile  = Join-Path $domainDir "OU_Changes_$nowStamp.txt"            # Change report

    Write-Output "INFO: Processing domain $domainTrimmed"

    #region Query Domain
    # Get the default naming context (base DN) for the domain
    $defaultNC = $null
    try {
        $rootDse = Get-ADRootDSE -Server $domainTrimmed -ErrorAction Stop
        $defaultNC = $rootDse.defaultNamingContext
    } catch {
        Write-Output "ERROR: $domainTrimmed - Failed to query RootDSE."
        $scriptExitCode = 1
        continue
    }

    if (-not $defaultNC) {
        Write-Output "ERROR: $domainTrimmed - defaultNamingContext not returned."
        $scriptExitCode = 1
        continue
    }

    # Query all OUs in the domain with required properties
    $currentSnapshot = @()
    try {
        $ous = Get-ADOrganizationalUnit -Server $domainTrimmed -SearchBase $defaultNC -Filter * `
            -SearchScope Subtree -Properties gPLink, gPOptions, ProtectedFromAccidentalDeletion -ErrorAction Stop
    } catch {
        Write-Output "ERROR: $domainTrimmed - Failed to query OUs."
        $scriptExitCode = 1
        continue
    }

    # Build snapshot objects from queried OUs
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
    #endregion

    #region Save Current Snapshot
    # Export current snapshot to timestamped CSV file
    try {
        $currentSnapshot |
            Sort-Object ObjectGUID |
            Export-Csv -Path $snapshotCsv -NoTypeInformation -Encoding UTF8
    } catch {
        Write-Output "ERROR: $domainTrimmed - Failed to write snapshot CSV: $snapshotCsv"
        $scriptExitCode = 1
        continue
    }
    #endregion

    #region Load Previous Snapshot
    # Load previous snapshot if it exists (for comparison)
    $previousSnapshot = @()
    if (Test-Path -LiteralPath $latestCsv) {
        try {
            $previousSnapshot = Import-Csv -Path $latestCsv
        } catch {
            Write-Output "ERROR: $domainTrimmed - Failed to read previous snapshot: $latestCsv"
            $scriptExitCode = 1
            $previousSnapshot = @()
        }
    }
    #endregion

    #region Build Lookup Hashtables
    # Build hashtables for fast lookup by GUID
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
    #endregion

    #region Detect Changes
    # Get GUID sets for comparison
    $prevGuids = $prevByGuid.Keys
    $currGuids = $currByGuid.Keys

    # Detect added and removed OUs by comparing GUID presence
    $addedGuids   = @($currGuids | Where-Object { -not $prevGuids -contains $_ })
    $removedGuids = @($prevGuids | Where-Object { -not $currGuids -contains $_ })

    # Initialize change tracking lists
    $renamed     = New-Object System.Collections.Generic.List[object]
    $moved       = New-Object System.Collections.Generic.List[object]
    $gpoChanged  = New-Object System.Collections.Generic.List[object]
    $protChanged = New-Object System.Collections.Generic.List[object]

    # Process each OU that exists in both snapshots (potential changes)
    foreach ($guid in $currGuids) {

        # Skip if this is a new OU (already in $addedGuids)
        if (-not $prevByGuid.ContainsKey($guid)) { continue }

        $prev = $prevByGuid[$guid]
        $curr = $currByGuid[$guid]

        $prevDN = $prev.DistinguishedName
        $currDN = $curr.DistinguishedName

        #region Detect Renames and Moves
        # Check if Distinguished Name changed (indicates rename or move)
        if ($prevDN -ne $currDN) {
            # Split DN into components (comma-separated, respecting escaped commas)
            $prevParts = $prevDN -split '(?<!\\),'
            $currParts = $currDN -split '(?<!\\),'

            # Extract RDN (Relative Distinguished Name - first component)
            $prevRdn = if ($prevParts.Count -gt 0) { $prevParts[0] } else { $null }
            $currRdn = if ($currParts.Count -gt 0) { $currParts[0] } else { $null }

            # Extract parent DN (everything after the RDN)
            $prevParent = if ($prevParts.Count -gt 1) { ($prevParts[1..($prevParts.Count - 1)] -join ',') } else { '' }
            $currParent = if ($currParts.Count -gt 1) { ($currParts[1..($currParts.Count - 1)] -join ',') } else { '' }

            # Classify the change type
            if ($prevParent -ne $currParent -and $prevRdn -eq $currRdn) {
                # Parent changed but name stayed same = Move
                $moved.Add([PSCustomObject]@{
                    ObjectGUID = $guid
                    OldDN      = $prevDN
                    NewDN      = $currDN
                })
            } elseif ($prevRdn -ne $currRdn -and $prevParent -eq $currParent) {
                # Name changed but parent stayed same = Rename
                $renamed.Add([PSCustomObject]@{
                    ObjectGUID = $guid
                    OldDN      = $prevDN
                    NewDN      = $currDN
                })
            } else {
                # Both changed = Move AND Rename
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
        #endregion

        #region Detect GPO Link Changes (CyberArk only)
        $prevGpLink = $prev.gPLink
        $currGpLink = $curr.gPLink
        $prevGpOpt  = $prev.gPOptions
        $currGpOpt  = $curr.gPOptions

        # Check if gPLink or gPOptions changed
        if ($prevGpLink -ne $currGpLink -or $prevGpOpt -ne $currGpOpt) {

            # Extract GPO GUIDs from both snapshots
            $prevGuidsGpo = Get-GpoGuidsFromGpLink -gpLinkString $prevGpLink
            $currGuidsGpo = Get-GpoGuidsFromGpLink -gpLinkString $currGpLink

            # Find GPO GUIDs that were added or removed
            $diffGuids = @()
            $diffGuids += ($currGuidsGpo | Where-Object { $_ -notin $prevGuidsGpo })  # Added
            $diffGuids += ($prevGuidsGpo | Where-Object { $_ -notin $currGuidsGpo })  # Removed

            # Check if any changed GPOs are CyberArk-related
            $changedCyberArk = New-Object System.Collections.Generic.List[object]

            foreach ($gGuid in $diffGuids) {
                try {
                    # Resolve GPO GUID to GPO object to get DisplayName
                    $gpo = Get-GPO -Guid $gGuid -Domain $domainTrimmed -ErrorAction Stop
                    
                    # Filter: only report if GPO name contains "CyberArk"
                    if ($gpo.DisplayName -match 'CyberArk') {
                        $changedCyberArk.Add([PSCustomObject]@{
                            GpoGuid = $gGuid
                            GpoName = $gpo.DisplayName
                        })
                    }
                } catch {
                    # Silently ignore GPO resolution failures (may be deleted)
                }
            }

            # Record CyberArk GPO changes for this OU
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
        #endregion

        #region Detect Protection Status Changes
        # Check if accidental deletion protection changed
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
        #endregion
    }
    #endregion

    #region Generate Change Report
    # Build report content as list of strings
    $reportLines = New-Object System.Collections.Generic.List[string]
    $reportLines.Add("Domain: $domainTrimmed")
    $reportLines.Add("RunTime: $($now.ToString('yyyy-MM-dd HH:mm:ss'))")
    $reportLines.Add("")

    $changesFound = $false

    # Added OUs
    $reportLines.Add("Added OUs (new objects):")
    if ($addedGuids.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($guid in $addedGuids) {
            $ou = $currByGuid[$guid]
            $reportLines.Add("  + $($ou.DistinguishedName)  GUID=$($ou.ObjectGUID)")
        }
    }

    # Removed OUs
    $reportLines.Add("")
    $reportLines.Add("Removed OUs (missing objects):")
    if ($removedGuids.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($guid in $removedGuids) {
            $ou = $prevByGuid[$guid]
            $reportLines.Add("  - $($ou.DistinguishedName)  GUID=$($ou.ObjectGUID)")
        }
    }

    # Renamed OUs
    $reportLines.Add("")
    $reportLines.Add("Renamed OUs (same parent, different RDN):")
    if ($renamed.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($r in $renamed) {
            $reportLines.Add("  REN GUID=$($r.ObjectGUID)")
            $reportLines.Add("      Old: $($r.OldDN)")
            $reportLines.Add("      New: $($r.NewDN)")
        }
    }

    # Moved OUs
    $reportLines.Add("")
    $reportLines.Add("Moved OUs (different parent):")
    if ($moved.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($m in $moved) {
            $reportLines.Add("  MOV GUID=$($m.ObjectGUID)")
            $reportLines.Add("      Old: $($m.OldDN)")
            $reportLines.Add("      New: $($m.NewDN)")
        }
    }

    # CyberArk GPO Changes
    $reportLines.Add("")
    $reportLines.Add("CyberArk GPO changes (gPLink / gPOptions):")
    if ($gpoChanged.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($g in $gpoChanged) {
            $reportLines.Add("  GPO GUID=$($g.GpoGuid)")
            $reportLines.Add("      Name: $($g.GpoName)")
            $reportLines.Add("      OU DN: $($g.DistinguishedName)")
            $reportLines.Add("      Old gPLink: $($g.OldgPLink)")
            $reportLines.Add("      New gPLink: $($g.NewgPLink)")
            $reportLines.Add("      Old gPOptions: $($g.OldgPOptions)")
            $reportLines.Add("      New gPOptions: $($g.NewgPOptions)")
        }
    }

    # Protection Status Changes
    $reportLines.Add("")
    $reportLines.Add("Accidental deletion protection changes:")
    if ($protChanged.Count -eq 0) {
        $reportLines.Add("  [none]")
    } else {
        $changesFound = $true
        foreach ($p in $protChanged) {
            $reportLines.Add("  PROT GUID=$($p.ObjectGUID)")
            $reportLines.Add("      DN: $($p.DistinguishedName)")
            $reportLines.Add("      Old Protected: $($p.OldProtected)")
            $reportLines.Add("      New Protected: $($p.NewProtected)")
        }
    }

    # Add notes for first-run scenarios
    if (-not (Test-Path -LiteralPath $latestCsv) -and $currentSnapshot.Count -eq 0) {
        $reportLines.Add("")
        $reportLines.Add("Note: first run for this domain and no OUs returned.")
    } elseif (-not (Test-Path -LiteralPath $latestCsv)) {
        $reportLines.Add("")
        $reportLines.Add("Note: first run for this domain. All OUs will appear as baseline only.")
    }
    #endregion

    #region Save Report and Update Latest Snapshot
    # Write change report to text file
    try {
        $reportLines | Out-File -FilePath $reportFile -Encoding UTF8
    } catch {
        Write-Output "ERROR: $domainTrimmed - Failed to write report file: $reportFile"
        $scriptExitCode = 1
    }

    # Move current snapshot to become the new "latest" snapshot for next run
    try {
        Move-Item -LiteralPath $snapshotCsv -Destination $latestCsv -Force
    } catch {
        Write-Output "ERROR: $domainTrimmed - Failed to update latest snapshot CSV: $latestCsv"
        $scriptExitCode = 1
    }
    #endregion

    #region Log Results
    # Log summary to output stream (for Autosys/scheduled task logs)
    if (-not $changesFound) {
        Write-Output "INFO: $domainTrimmed - No OU structural changes detected."
    } else {
        Write-Output "INFO: $domainTrimmed - OU structural changes detected. Report: $reportFile"
    }
    #endregion
}
#endregion

# Exit with accumulated error code (0 = success, 1 = one or more errors occurred)
exit $scriptExitCode
