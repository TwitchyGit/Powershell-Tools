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
    [string]$ADGroupName,
    
    [Parameter(Mandatory=$true)]
    [string]$CyberArkURL,
    
    [Parameter(Mandatory=$true)]
    [string]$Region,
    
    [switch]$AutoReconcile,
    
    [string]$LogPath = "C:\Temp\ADCyberArkCompare_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
)

# Function to write log
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogPath -Value $logMessage
}

try {
    # Import required modules
    Write-Log "Importing required modules..."
    Import-Module ActiveDirectory -ErrorAction Stop
    Import-Module psPAS -ErrorAction Stop
    
    Write-Log "Starting comparison for Region: $Region" "INFO"
    Write-Log ("=" * 80)
    
    # Get AD Group Members filtered by region
    Write-Log "Retrieving AD group members from: $ADGroupName"
    $adUsers = Get-ADGroupMember -Identity $ADGroupName -Recursive | 
               Get-ADUser -Properties SamAccountName, DisplayName, mail, c, co | 
               Where-Object { $_.c -eq $Region -or $_.co -eq $Region }
    
    Write-Log "Found $($adUsers.Count) AD users in region $Region"
    
    # Connect to CyberArk
    Write-Log "Connecting to CyberArk at: $CyberArkURL"
    $creds = Get-Credential -Message "Enter CyberArk credentials"
    
    New-PASSession -BaseURI $CyberArkURL -Credential $creds -type CyberArk -ErrorAction Stop
    Write-Log "Connected to CyberArk successfully"
    
    # Get CyberArk external users filtered by region
    Write-Log "Retrieving CyberArk external users for region: $Region"
    $cyberArkUsers = Get-PASUser -UserType EPVUser -ExtendedDetails $true | 
                     Where-Object { $_.Location -eq $Region }
    
    Write-Log "Found $($cyberArkUsers.Count) CyberArk users in region $Region"
    
    # Create comparison lists
    $adUserNames = $adUsers | Select-Object -ExpandProperty SamAccountName
    $cyberArkUserNames = $cyberArkUsers | Select-Object -ExpandProperty UserName
    
    # Find discrepancies
    $inADNotInCyberArk = $adUserNames | Where-Object { $_ -notin $cyberArkUserNames }
    $inCyberArkNotInAD = $cyberArkUserNames | Where-Object { $_ -notin $adUserNames }
    
    Write-Log ("=" * 80)
    Write-Log "COMPARISON RESULTS FOR REGION: $Region" "INFO"
    Write-Log ("=" * 80)
    
    # Display users in AD but not in CyberArk
    if ($inADNotInCyberArk.Count -gt 0) {
        Write-Log "Users in AD group but NOT in CyberArk ($($inADNotInCyberArk.Count)):" "WARNING"
        foreach ($user in $inADNotInCyberArk) {
            $adUser = $adUsers | Where-Object { $_.SamAccountName -eq $user }
            Write-Log "  - $user ($($adUser.DisplayName)) - $($adUser.mail)" "WARNING"
        }
        Write-Log ""
    } else {
        Write-Log "All AD users exist in CyberArk" "INFO"
    }
    
    # Display users in CyberArk but not in AD
    if ($inCyberArkNotInAD.Count -gt 0) {
        Write-Log "Users in CyberArk but NOT in AD group ($($inCyberArkNotInAD.Count)):" "WARNING"
        foreach ($user in $inCyberArkNotInAD) {
            $cyberArkUser = $cyberArkUsers | Where-Object { $_.UserName -eq $user }
            Write-Log "  - $user ($($cyberArkUser.FirstName) $($cyberArkUser.LastName))" "WARNING"
        }
        Write-Log ""
    } else {
        Write-Log "All CyberArk users exist in AD" "INFO"
    }
    
    Write-Log ("=" * 80)
    
    # Reconciliation prompt
    if (($inADNotInCyberArk.Count -gt 0 -or $inCyberArkNotInAD.Count -gt 0) -and -not $AutoReconcile) {
        Write-Host "`nDiscrepancies found. Would you like to reconcile?" -ForegroundColor Yellow
        Write-Host "1. Add missing users to CyberArk"
        Write-Host "2. Remove extra users from CyberArk"
        Write-Host "3. Both (add missing and remove extra)"
        Write-Host "4. Skip reconciliation"
        
        $choice = Read-Host "Enter your choice (1-4)"
        
        switch ($choice) {
            "1" {
                # Add users to CyberArk
                Write-Log "Adding users to CyberArk..." "INFO"
                foreach ($user in $inADNotInCyberArk) {
                    $adUser = $adUsers | Where-Object { $_.SamAccountName -eq $user }
                    
                    $confirmation = Read-Host "Add $user ($($adUser.DisplayName)) to CyberArk? (Y/N)"
                    if ($confirmation -eq 'Y') {
                        try {
                            # Example: Adjust parameters based on your CyberArk setup
                            New-PASUser -UserName $user -UserType EPVUser `
                                        -InitialPassword (Read-Host "Enter initial password for $user" -AsSecureString) `
                                        -Email $adUser.mail `
                                        -FirstName $adUser.GivenName `
                                        -LastName $adUser.Surname `
                                        -Location $Region `
                                        -ErrorAction Stop
                            
                            Write-Log "Successfully added $user to CyberArk" "INFO"
                        } catch {
                            Write-Log "Failed to add $user to CyberArk: $_" "ERROR"
                        }
                    } else {
                        Write-Log "Skipped adding $user" "INFO"
                    }
                }
            }
            
            "2" {
                # Remove users from CyberArk
                Write-Log "Removing users from CyberArk..." "INFO"
                foreach ($user in $inCyberArkNotInAD) {
                    $confirmation = Read-Host "Remove $user from CyberArk? (Y/N)"
                    if ($confirmation -eq 'Y') {
                        try {
                            Remove-PASUser -UserName $user -ErrorAction Stop
                            Write-Log "Successfully removed $user from CyberArk" "INFO"
                        } catch {
                            Write-Log "Failed to remove $user from CyberArk: $_" "ERROR"
                        }
                    } else {
                        Write-Log "Skipped removing $user" "INFO"
                    }
                }
            }
            
            "3" {
                # Both add and remove
                Write-Log "Performing full reconciliation..." "INFO"
                
                # Add missing users
                foreach ($user in $inADNotInCyberArk) {
                    $adUser = $adUsers | Where-Object { $_.SamAccountName -eq $user }
                    $confirmation = Read-Host "Add $user to CyberArk? (Y/N)"
                    if ($confirmation -eq 'Y') {
                        try {
                            New-PASUser -UserName $user -UserType EPVUser `
                                        -InitialPassword (Read-Host "Enter initial password for $user" -AsSecureString) `
                                        -Email $adUser.mail `
                                        -FirstName $adUser.GivenName `
                                        -LastName $adUser.Surname `
                                        -Location $Region `
                                        -ErrorAction Stop
                            Write-Log "Successfully added $user to CyberArk" "INFO"
                        } catch {
                            Write-Log "Failed to add $user: $_" "ERROR"
                        }
                    }
                }
                
                # Remove extra users
                foreach ($user in $inCyberArkNotInAD) {
                    $confirmation = Read-Host "Remove $user from CyberArk? (Y/N)"
                    if ($confirmation -eq 'Y') {
                        try {
                            Remove-PASUser -UserName $user -ErrorAction Stop
                            Write-Log "Successfully removed $user from CyberArk" "INFO"
                        } catch {
                            Write-Log "Failed to remove $user: $_" "ERROR"
                        }
                    }
                }
            }
            
            "4" {
                Write-Log "Reconciliation skipped by user" "INFO"
            }
            
            default {
                Write-Log "Invalid choice. Skipping reconciliation" "WARNING"
            }
        }
    } elseif ($inADNotInCyberArk.Count -eq 0 -and $inCyberArkNotInAD.Count -eq 0) {
        Write-Log "No discrepancies found. AD and CyberArk are in sync!" "INFO"
    }
    
    # Close CyberArk session
    Close-PASSession
    Write-Log "CyberArk session closed"
    
} catch {
    Write-Log "ERROR: $_" "ERROR"
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
} finally {
    Write-Log ("=" * 80)
    Write-Log "Script completed. Log saved to: $LogPath" "INFO"
}

# Export summary report
$report = [PSCustomObject]@{
    Region = $Region
    ADGroupName = $ADGroupName
    TotalADUsers = $adUsers.Count
    TotalCyberArkUsers = $cyberArkUsers.Count
    InADNotInCyberArk = $inADNotInCyberArk.Count
    InCyberArkNotInAD = $inCyberArkNotInAD.Count
    Timestamp = Get-Date
}

$reportPath = "C:\Temp\ADCyberArkReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$report | Export-Csv -Path $reportPath -NoTypeInformation
Write-Log "Summary report exported to: $reportPath" "INFO"
