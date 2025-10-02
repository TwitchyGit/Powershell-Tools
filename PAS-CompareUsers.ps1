# Compare AD Group Members with CyberArk PAM External Users by Region
# Requires: ActiveDirectory module and psPAS module
# .\PAS-CompareUsers.ps1 -ADGroupName "CyberArk_EMEA_Users" `
#                           -CyberArkURL "https://pvwa.company.com" `
#                           -Region "EMEA"
# Compare multiple regions:
# $regions = @("EMEA", "APAC", "AMER")
# foreach ($region in $regions) {
#     .\PAS-CompareUsers.ps1 -ADGroupName "CyberArk_$region_Users" `
#                               -CyberArkURL "https://pvwa.company.com" `
#                               -Region $region
# }
#
# .\Compare-ADCyberArk.ps1 -ADGroupName "CyberArk_EMEA_Users" `
#                           -CyberArkURL "https://pvwa.company.com" `
#                           -Region "EMEA" `
#                           -LogPath "D:\Logs\CyberArk\comparison.log"

param(
    [Parameter(Mandatory=$true)]
    [string]$ConfigModule,
    
    [Parameter(Mandatory=$true)]
    [string]$CredentialFile,
    
    [Parameter(Mandatory=$true)]
    [string]$CyberArkURL,
    
    [string]$LogPath = "C:\Temp\ADCyberArkCompare_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# Suppress all warning and information streams for Autosys
$WarningPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'

# Function to write to stdout only
function Write-Output-Safe {
    param([string]$Message)
    Write-Output $Message
    if ($LogPath) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogPath -Value "[$timestamp] $Message" -ErrorAction SilentlyContinue
    }
}

# Function to write to stderr for errors
function Write-Error-Safe {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
    if ($LogPath) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $LogPath -Value "[$timestamp] [ERROR] $Message" -ErrorAction SilentlyContinue
    }
}

# Function to securely clear credentials from memory
function Clear-Credentials {
    param($Credential)
    if ($Credential -ne $null) {
        $Credential.Password.Dispose()
        $Credential = $null
    }
}

try {
    # Import required modules
    Import-Module ActiveDirectory -ErrorAction Stop 2>$null
    Import-Module psPAS -ErrorAction Stop 2>$null
    
    Write-Output-Safe "Starting AD and CyberArk comparison"
    Write-Output-Safe "================================================================================"
    
    # Import configuration module
    Write-Output-Safe "Importing configuration from: $ConfigModule"
    if (-not (Test-Path $ConfigModule)) {
        throw "Configuration module not found: $ConfigModule"
    }
    Import-Module $ConfigModule -Force -ErrorAction Stop 2>$null
    
    # Validate configuration variables
    if (-not $regions) {
        throw "Variable `$regions not found in configuration module"
    }
    if (-not $ADGroups) {
        throw "Variable `$ADGroups not found in configuration module"
    }
    
    Write-Output-Safe "Regions to process: $($regions -join ', ')"
    Write-Output-Safe "AD Groups to process: $($ADGroups -join ', ')"
    
    # Import credentials securely from CliXml
    Write-Output-Safe "Importing credentials from: $CredentialFile"
    if (-not (Test-Path $CredentialFile)) {
        throw "Credential file not found: $CredentialFile"
    }
    $creds = Import-Clixml -Path $CredentialFile -ErrorAction Stop
    Write-Output-Safe "Credentials imported successfully"
    
    # Get all AD users from all specified groups
    Write-Output-Safe "Retrieving AD group members from all specified groups..."
    $allADUsers = @()
    $adUserHash = @{}
    
    foreach ($group in $ADGroups) {
        Write-Output-Safe "Processing AD group: $group"
        try {
            $groupMembers = Get-ADGroupMember -Identity $group -Recursive -ErrorAction Stop 2>$null | 
                           Get-ADUser -Properties SamAccountName, DisplayName, mail, c, co -ErrorAction Stop 2>$null
            
            foreach ($user in $groupMembers) {
                # Use hash to avoid duplicates across multiple groups
                if (-not $adUserHash.ContainsKey($user.SamAccountName)) {
                    $adUserHash[$user.SamAccountName] = $user
                    $allADUsers += $user
                }
            }
            Write-Output-Safe "  Found $($groupMembers.Count) members in $group"
        } catch {
            Write-Error-Safe "Failed to process AD group ${group}: $($_.Exception.Message)"
        }
    }
    
    Write-Output-Safe "Total unique AD users found: $($allADUsers.Count)"
    
    # Connect to CyberArk
    Write-Output-Safe "Connecting to CyberArk at: $CyberArkURL"
    try {
        New-PASSession -BaseURI $CyberArkURL -Credential $creds -type CyberArk -ErrorAction Stop 2>$null
        Write-Output-Safe "Connected to CyberArk successfully"
    } catch {
        throw "Failed to connect to CyberArk: $($_.Exception.Message)"
    } finally {
        # Clear credentials from memory immediately after use
        Clear-Credentials -Credential $creds
        $creds = $null
        Write-Output-Safe "Credentials cleared from memory"
    }
    
    # Get all CyberArk external users where Location contains any of the regions
    Write-Output-Safe "Retrieving CyberArk external users for all regions..."
    $allCyberArkUsers = Get-PASUser -UserType EPVUser -ExtendedDetails $true -ErrorAction Stop 2>$null
    
    # Filter users by region (Location contains region)
    $filteredCyberArkUsers = @()
    foreach ($user in $allCyberArkUsers) {
        foreach ($region in $regions) {
            if ($user.Location -like "*$region*") {
                $filteredCyberArkUsers += $user
                break
            }
        }
    }
    
    Write-Output-Safe "Total CyberArk users matching regions: $($filteredCyberArkUsers.Count)"
    
    # Create comparison lists
    $adUserNames = $allADUsers | Select-Object -ExpandProperty SamAccountName | Sort-Object -Unique
    $cyberArkUserNames = $filteredCyberArkUsers | Select-Object -ExpandProperty UserName | Sort-Object -Unique
    
    # Find discrepancies
    $inADNotInCyberArk = $adUserNames | Where-Object { $_ -notin $cyberArkUserNames }
    $inCyberArkNotInAD = $cyberArkUserNames | Where-Object { $_ -notin $adUserNames }
    
    Write-Output-Safe ""
    Write-Output-Safe "================================================================================"
    Write-Output-Safe "COMPARISON RESULTS - ALL REGIONS: $($regions -join ', ')"
    Write-Output-Safe "================================================================================"
    Write-Output-Safe ""
    
    # Display users in AD but not in CyberArk
    Write-Output-Safe ">>> USERS IN AD GROUPS BUT NOT IN CYBERARK <<<"
    Write-Output-Safe "-------------------------------------------------------------------------------"
    if ($inADNotInCyberArk.Count -gt 0) {
        Write-Output-Safe "Count: $($inADNotInCyberArk.Count)"
        Write-Output-Safe ""
        foreach ($user in $inADNotInCyberArk) {
            $adUser = $allADUsers | Where-Object { $_.SamAccountName -eq $user } | Select-Object -First 1
            $displayName = if ($adUser.DisplayName) { $adUser.DisplayName } else { "N/A" }
            $email = if ($adUser.mail) { $adUser.mail } else { "N/A" }
            $country = if ($adUser.c) { $adUser.c } elseif ($adUser.co) { $adUser.co } else { "N/A" }
            Write-Output-Safe "$user, $displayName, $email, $country"
        }
    } else {
        Write-Output-Safe "None - All AD users exist in CyberArk"
    }
    Write-Output-Safe ""
    
    # Display users in CyberArk but not in AD
    Write-Output-Safe ">>> USERS IN CYBERARK BUT NOT IN AD GROUPS <<<"
    Write-Output-Safe "-------------------------------------------------------------------------------"
    if ($inCyberArkNotInAD.Count -gt 0) {
        Write-Output-Safe "Count: $($inCyberArkNotInAD.Count)"
        Write-Output-Safe ""
        foreach ($user in $inCyberArkNotInAD) {
            $cyberArkUser = $filteredCyberArkUsers | Where-Object { $_.UserName -eq $user } | Select-Object -First 1
            $firstName = if ($cyberArkUser.FirstName) { $cyberArkUser.FirstName } else { "" }
            $lastName = if ($cyberArkUser.LastName) { $cyberArkUser.LastName } else { "" }
            $fullName = "$firstName $lastName".Trim()
            if (-not $fullName) { $fullName = "N/A" }
            $email = if ($cyberArkUser.Email) { $cyberArkUser.Email } else { "N/A" }
            $location = if ($cyberArkUser.Location) { $cyberArkUser.Location } else { "N/A" }
            Write-Output-Safe "$user, $fullName, $email, $location"
        }
    } else {
        Write-Output-Safe "None - All CyberArk users exist in AD"
    }
    Write-Output-Safe ""
    
    # Summary by region
    Write-Output-Safe "================================================================================"
    Write-Output-Safe "SUMMARY BY REGION"
    Write-Output-Safe "================================================================================"
    
    foreach ($region in $regions) {
        $regionADUsers = $allADUsers | Where-Object { $_.c -eq $region -or $_.co -eq $region }
        $regionCyberArkUsers = $filteredCyberArkUsers | Where-Object { $_.Location -like "*$region*" }
        
        Write-Output-Safe "Region: $region"
        Write-Output-Safe "  AD Users: $($regionADUsers.Count)"
        Write-Output-Safe "  CyberArk Users: $($regionCyberArkUsers.Count)"
        Write-Output-Safe ""
    }
    
    # Overall Summary
    Write-Output-Safe "================================================================================"
    Write-Output-Safe "OVERALL SUMMARY"
    Write-Output-Safe "================================================================================"
    Write-Output-Safe "Regions Processed: $($regions -join ', ')"
    Write-Output-Safe "AD Groups Processed: $($ADGroups -join ', ')"
    Write-Output-Safe "Total Unique AD Users: $($adUserNames.Count)"
    Write-Output-Safe "Total CyberArk Users (filtered): $($cyberArkUserNames.Count)"
    Write-Output-Safe "In AD but not CyberArk: $($inADNotInCyberArk.Count)"
    Write-Output-Safe "In CyberArk but not AD: $($inCyberArkNotInAD.Count)"
    Write-Output-Safe "================================================================================"
    
    # Close CyberArk session
    Close-PASSession 2>$null
    Write-Output-Safe "CyberArk session closed"
    
    # Export detailed report
    $detailsReport = @()
    
    foreach ($user in $inADNotInCyberArk) {
        $adUser = $allADUsers | Where-Object { $_.SamAccountName -eq $user } | Select-Object -First 1
        $country = if ($adUser.c) { $adUser.c } elseif ($adUser.co) { $adUser.co } else { "N/A" }
        $detailsReport += [PSCustomObject]@{
            Username = $user
            DisplayName = $adUser.DisplayName
            Email = $adUser.mail
            Country = $country
            Location = "AD Only"
        }
    }
    
    foreach ($user in $inCyberArkNotInAD) {
        $cyberArkUser = $filteredCyberArkUsers | Where-Object { $_.UserName -eq $user } | Select-Object -First 1
        $detailsReport += [PSCustomObject]@{
            Username = $user
            DisplayName = "$($cyberArkUser.FirstName) $($cyberArkUser.LastName)".Trim()
            Email = $cyberArkUser.Email
            Country = "N/A"
            Location = $cyberArkUser.Location
        }
    }
    
    if ($detailsReport.Count -gt 0) {
        $reportPath = "C:\Temp\ADCyberArkDiscrepancies_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
        $detailsReport | Export-Csv -Path $reportPath -NoTypeInformation -ErrorAction SilentlyContinue
        Write-Output-Safe "Detailed report exported to: $reportPath"
    }
    
    Write-Output-Safe "Script completed. Log saved to: $LogPath"
    
    # Exit code 0 for success
    exit 0
    
} catch {
    Write-Error-Safe "ERROR: $($_.Exception.Message)"
    Write-Error-Safe "Script failed at line $($_.InvocationInfo.ScriptLineNumber)"
    
    # Ensure credentials are cleared even on error
    if ($creds -ne $null) {
        Clear-Credentials -Credential $creds
        $creds = $null
    }
    
    # Exit code 1 for failure
    exit 1
}
