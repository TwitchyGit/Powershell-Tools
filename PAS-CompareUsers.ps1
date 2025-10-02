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

# Compare AD Group Members with CyberArk PAM External Users by Region
# PowerShell 5.1 compatible - Autosys ready (stdout/stderr only)
# Requires: ActiveDirectory module and psPAS module

param(
    [Parameter(Mandatory=$true)]
    [string]$ADGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$CyberArkURL,
    
    [Parameter(Mandatory=$true)]
    [string]$Region,
    
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

try {
    # Import required modules
    Import-Module ActiveDirectory -ErrorAction Stop 2>$null
    Import-Module psPAS -ErrorAction Stop 2>$null
    
    Write-Output-Safe "Starting comparison for Region: $Region"
    Write-Output-Safe "================================================================================"
    
    # Get AD Group Members filtered by region
    Write-Output-Safe "Retrieving AD group members from: $ADGroupName"
    $adUsers = Get-ADGroupMember -Identity $ADGroupName -Recursive -ErrorAction Stop 2>$null | 
               Get-ADUser -Properties SamAccountName, DisplayName, mail, c, co -ErrorAction Stop 2>$null | 
               Where-Object { $_.c -eq $Region -or $_.co -eq $Region }
    
    Write-Output-Safe "Found $($adUsers.Count) AD users in region $Region"
    
    # Connect to CyberArk
    Write-Output-Safe "Connecting to CyberArk at: $CyberArkURL"
    $creds = Get-Credential -Message "Enter CyberArk credentials"
    
    New-PASSession -BaseURI $CyberArkURL -Credential $creds -type CyberArk -ErrorAction Stop 2>$null
    Write-Output-Safe "Connected to CyberArk successfully"
    
    # Get CyberArk external users filtered by region
    Write-Output-Safe "Retrieving CyberArk external users for region: $Region"
    $cyberArkUsers = Get-PASUser -UserType EPVUser -ExtendedDetails $true -ErrorAction Stop 2>$null | 
                     Where-Object { $_.Location -eq $Region }
    
    Write-Output-Safe "Found $($cyberArkUsers.Count) CyberArk users in region $Region"
    
    # Create comparison lists
    $adUserNames = $adUsers | Select-Object -ExpandProperty SamAccountName
    $cyberArkUserNames = $cyberArkUsers | Select-Object -ExpandProperty UserName
    
    # Find discrepancies
    $inADNotInCyberArk = $adUserNames | Where-Object { $_ -notin $cyberArkUserNames }
    $inCyberArkNotInAD = $cyberArkUserNames | Where-Object { $_ -notin $adUserNames }
    
    Write-Output-Safe ""
    Write-Output-Safe "================================================================================"
    Write-Output-Safe "COMPARISON RESULTS FOR REGION: $Region"
    Write-Output-Safe "================================================================================"
    Write-Output-Safe ""
    
    # Display users in AD but not in CyberArk
    Write-Output-Safe ">>> USERS IN AD GROUP BUT NOT IN CYBERARK <<<"
    Write-Output-Safe "-------------------------------------------------------------------------------"
    if ($inADNotInCyberArk.Count -gt 0) {
        Write-Output-Safe "Count: $($inADNotInCyberArk.Count)"
        Write-Output-Safe ""
        foreach ($user in $inADNotInCyberArk) {
            $adUser = $adUsers | Where-Object { $_.SamAccountName -eq $user }
            $displayName = if ($adUser.DisplayName) { $adUser.DisplayName } else { "N/A" }
            $email = if ($adUser.mail) { $adUser.mail } else { "N/A" }
            Write-Output-Safe "$user, $displayName, $email"
        }
    } else {
        Write-Output-Safe "None - All AD users exist in CyberArk"
    }
    Write-Output-Safe ""
    
    # Display users in CyberArk but not in AD
    Write-Output-Safe ">>> USERS IN CYBERARK BUT NOT IN AD GROUP <<<"
    Write-Output-Safe "-------------------------------------------------------------------------------"
    if ($inCyberArkNotInAD.Count -gt 0) {
        Write-Output-Safe "Count: $($inCyberArkNotInAD.Count)"
        Write-Output-Safe ""
        foreach ($user in $inCyberArkNotInAD) {
            $cyberArkUser = $cyberArkUsers | Where-Object { $_.UserName -eq $user }
            $firstName = if ($cyberArkUser.FirstName) { $cyberArkUser.FirstName } else { "" }
            $lastName = if ($cyberArkUser.LastName) { $cyberArkUser.LastName } else { "" }
            $fullName = "$firstName $lastName".Trim()
            if (-not $fullName) { $fullName = "N/A" }
            $email = if ($cyberArkUser.Email) { $cyberArkUser.Email } else { "N/A" }
            Write-Output-Safe "$user, $fullName, $email"
        }
    } else {
        Write-Output-Safe "None - All CyberArk users exist in AD"
    }
    Write-Output-Safe ""
    
    # Summary
    Write-Output-Safe "================================================================================"
    Write-Output-Safe "SUMMARY"
    Write-Output-Safe "================================================================================"
    Write-Output-Safe "Region: $Region"
    Write-Output-Safe "AD Group: $ADGroupName"
    Write-Output-Safe "Total AD Users: $($adUsers.Count)"
    Write-Output-Safe "Total CyberArk Users: $($cyberArkUsers.Count)"
    Write-Output-Safe "In AD but not CyberArk: $($inADNotInCyberArk.Count)"
    Write-Output-Safe "In CyberArk but not AD: $($inCyberArkNotInAD.Count)"
    Write-Output-Safe "================================================================================"
    
    # Close CyberArk session
    Close-PASSession 2>$null
    Write-Output-Safe "CyberArk session closed"
    
    # Export detailed report
    $detailsReport = @()
    
    foreach ($user in $inADNotInCyberArk) {
        $adUser = $adUsers | Where-Object { $_.SamAccountName -eq $user }
        $detailsReport += [PSCustomObject]@{
            Username = $user
            DisplayName = $adUser.DisplayName
            Email = $adUser.mail
            Location = "AD Only"
            Region = $Region
        }
    }
    
    foreach ($user in $inCyberArkNotInAD) {
        $cyberArkUser = $cyberArkUsers | Where-Object { $_.UserName -eq $user }
        $detailsReport += [PSCustomObject]@{
            Username = $user
            DisplayName = "$($cyberArkUser.FirstName) $($cyberArkUser.LastName)".Trim()
            Email = $cyberArkUser.Email
            Location = "CyberArk Only"
            Region = $Region
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
    
    # Exit code 1 for failure
    exit 1
}
