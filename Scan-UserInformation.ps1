$functionsModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Config/PSFunctions.psm1'

try {
    Import-Module -Name $functionsModulePath -Force -ErrorAction Stop
} catch {
    Write-Output "ERROR: Unable to import onboarding functions: $($_.Exception.Message)"
    if (Get-Command -Name Set-ReturnCode -ErrorAction SilentlyContinue) {
        Set-ReturnCode 1
    }
    return
}

Initialize-CybOnboardingContext -Configuration @{
    ConfPVWAURL  = $ConfPVWAURL
    PVWAAuthBody = $PVWAAuthBody
    LoginSplat   = $splat
}

# Force PowerShell console + outputs to UTF-8 for kanji handling
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
# Note: in PS5.1 'utf8' writes a BOM (which Excel needs); in PS6+ use 'utf8BOM' explicitly
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
$PSDefaultParameterValues['Export-Csv:Encoding'] = 'utf8'

# Log into Vault
if ($splat['Debug']) {
    LogMessage("DEBUG: New-Login -Authentication $($PVWAAuthBody.AuthBody.username)")
}
$result = New-Login -Authentication $PVWAAuthBody.AuthBody @splat
LogMessage("$($result.Message)")
if ($result.Return -eq $false) {
    Set-ReturnCode 1
    return
}

######################### Terminate if DryRun Specified ########################
if ($DryRun) {
    LogMessage("INFO: DryRun complete: No updates are performed.")
    $result = New-Logoff
    LogMessage("$($result.Message)")
    Set-ReturnCode 0    # Set to zero anyway for Dry Run.
    return
}

# List all users - note this is the /users api endpoint, containing only a subset of data.
# To retrieve the full user data, the report after will access /users/{0}
try {
    # Get-AllUsers returns hashtable in $AllUsers.users
    $result = Get-AllUsers
    Write-Debug "GOT: $($result.Data); $($result.Success); $($result.Data.Total) $($result.Data.Count)"
    if (-not $result.Success) {
        LogMessage("ERROR: Failed to retrieve users - $($result.Message)")
        Set-ReturnCode 1
        return
    }
    if ($null -eq $result.Data -or $result.Data.Total -eq 0) {
        LogMessage("ERROR: Failed to retrieve users - empty response (Total=$($result.Data.Total))")
        Set-ReturnCode 1
        return
    }

    $EPVUserList = $result.Data.users | Where-Object { $_.UserType -eq "EPVUser" -And $_.Source -like "LDAP" }
    LogMessage("INFO: Found $($EPVUserList.Count) EPVUser/LDAP users to process")
} catch {
    LogMessage("ERROR: $($_.Exception.Message)")
    $ValidateError = 1
}

if ($InDebug) {
    # See the structure
    $EPVUserList | Format-Table * -AutoSize
    # See the properties
    $EPVUserList[0].name
    # View the JSON
    $EPVUserList[0] | ConvertTo-Json -Depth 3
}

# Iterate users - only collect those with NO group membership (or failures).
$results = New-Object System.Collections.Generic.List[object]
$failedCount = 0
$noGroupsCount = 0
$processed = 0
$total = $EPVUserList.Count

foreach ($User in $EPVUserList) {
    if ($($User.userType) -ne "EPVUser") {
        Write-Debug "$User is not EPVUser"; continue
    }
    Write-Debug "Getting details for user: $($User.username)"
    $userId = $user.id
    $userName = $user.username

    $processed++
    if ($processed % 100 -eq 0) {
        LogMessage("INFO: Progress $processed / $total")
    }

    $result = Get-UserDetails -UserId $userId -UserName $userName
    if (-not $result.Success) {
        LogMessage($result.Message)
        $failedCount++
        $results.Add([PSCustomObject]@{
            UserName = $userName
            Status   = 'FAILED'
            Detail   = $result.Message
        })
        continue
    }

    if ($InDebug) {
        Write-Debug "User $($result.Data.username) (ID=$($result.Data.id)): groups after exclusions=$($result.GroupCount)"
        $result.Data | ConvertTo-Json -Depth 5
    }

    # Report users with no group membership after exclusions are applied.
    # This includes users who only belonged to groups excluded by the shared configuration.
    if ($result.GroupCount -eq 0) {
        $noGroupsCount++
        $results.Add([PSCustomObject]@{
            UserName = $userName
            Status   = 'NoGroupMembership'
            Detail   = ''
        })
    }
}

LogMessage("INFO: Completed - $total processed | $noGroupsCount NoGroupMembership | $failedCount failed")

# Output: comma-separated, one line per user, no truncation
"UserName,Status,Detail"
foreach ($row in $results) {
    "$($row.UserName),$($row.Status),$($row.Detail)"
}

########################## Logoff from the Vault ###############################
$result = New-Logoff @splat
LogMessage("$($result.Message)")
# Exit and trap any errors generated
if ($ValidateError -eq $true) {
    Set-ReturnCode 1
    return
} else {
    Set-ReturnCode 0
    return
}
