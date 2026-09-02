# Load the shared configuration relative to this script.
$configModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Config/ConfigModule.psm1'
Import-Module -Name $configModulePath -Force -ErrorAction Stop

$SafeFeedPath = $CybUserGroupAssignmentConfig.SafeFeedPath
$UserFeedPath = $CybUserGroupAssignmentConfig.UserFeedPath
$OutputPath = $CybUserGroupAssignmentConfig.OutputPath

# LOAD INPUTS
$SafeFeed = Import-Csv -Path $SafeFeedPath
$AllUsers = Get-Content $UserFeedPath | Where-Object { $_.Trim() -ne "" }

# GROUP SAFE FEED BY COMMON groupName PREFIX
# Bucket each row by its suffix: _Owner, _Mgr, _User, or other
$Groups = @{}

foreach ($Row in $SafeFeed) {
    $Name = $Row.groupName.Trim()

    if ($Name -match '^(.+)_(Owner|Mgr|User)$') {
        $Base   = $Matches[1]
        $Suffix = $Matches[2]
    }
    else {
        # Not a recognised suffix - pass through unchanged
        continue
    }

    if (-not $Groups.ContainsKey($Base)) {
        $Groups[$Base] = @{ O = $null; M = $null; U = $null }
    }

    $Groups[$Base][$Suffix] = $Row
}

# BUILD OUTPUT ROWS
$Output = [System.Collections.Generic.List[PSCustomObject]]::new()

# Pass through any rows that didn't match _Owner/_Mgr/_User pattern unchanged
foreach ($Row in $SafeFeed) {
    if ($Row.groupName -notmatch '^(.+)_(Owner|Mgr|User)$') {
        $Output.Add([PSCustomObject]@{
            id          = $Row.id
            groupName   = $Row.groupName
            description = $Row.description
            location    = $Row.location
            Members     = $Row.Members
        })
    }
}

foreach ($Base in $Groups.Keys) {
    $G = $Groups[$Base]

    # _Owner ROW: assign 1 random user, skip if no _Owner group
    if ($null -eq $G['O']) {
        # No _Owner group - skip _Mgr/_User entirely per spec
        continue
    }

    $ORow = $G['O']

    # Check if _Owner is flagged as NoUser or NoManager
    $OMembers     = $ORow.Members
    $OIsBlocked   = ($OMembers -match 'NoUser|NoManager')

    # Assign 1 random user to _Owner
    $OUser = if (-not $OIsBlocked) {
        ($AllUsers | Get-Random -Count 1).Trim()
    } else { "" }

    $Output.Add([PSCustomObject]@{
        id          = $ORow.id
        groupName   = $ORow.groupName
        description = $ORow.description
        location    = $ORow.location
        Members     = $OUser
    })

    # _Mgr and _User ROWS: skip entirely if _Owner is blocked
    if ($OIsBlocked) {
        # Still emit _Mgr/_User rows but with no members
        foreach ($Suffix in @('Mgr','User')) {
            $Row = $G[$Suffix]
            if ($null -eq $Row) { continue }
            $Output.Add([PSCustomObject]@{
                id          = $Row.id
                groupName   = $Row.groupName
                description = $Row.description
                location    = $Row.location
                Members     = ""
            })
        }
        continue
    }

    # Assign random count (0-20) of random users independently to _Mgr and _User
    foreach ($Suffix in @('Mgr','User')) {
        $Row = $G[$Suffix]
        if ($null -eq $Row) { continue }

        $Count       = Get-Random -Minimum 0 -Maximum 21
        $Assigned    = if ($Count -gt 0) {
            ($AllUsers | Get-Random -Count ([Math]::Min($Count, $AllUsers.Count)) | ForEach-Object { $_.Trim() }) -join ";"
        } else { "" }

        $Output.Add([PSCustomObject]@{
            id          = $Row.id
            groupName   = $Row.groupName
            description = $Row.description
            location    = $Row.location
            Members     = $Assigned
        })
    }
}

# EXPORT
$Output | Sort-Object groupName | Export-Csv -Path $OutputPath -NoTypeInformation
Write-Host "Done. $($Output.Count) rows written to $OutputPath"
