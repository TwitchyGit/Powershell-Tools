<#
.SYNOPSIS
    Gets all Group Policy Objects (GPOs) that apply to specified computer objects in Active Directory.

.DESCRIPTION
    This script queries Active Directory to find computer objects and determines which GPOs
    apply to them based on their OU location. It walks up the OU hierarchy to discover all
    linked GPOs, including their enabled status, enforcement, and link order.
    
    Note: This shows GPOs that SHOULD apply based on AD structure. It does not query the
    actual resultant set of policy (RSoP) from live machines.

.NOTES
    Requires: Active Directory and Group Policy PowerShell modules
#>

# Import only required commands to minimize module load time and memory footprint
Import-Module ActiveDirectory -Cmdlet Get-ADComputer
Import-Module GroupPolicy -Cmdlet Get-GPInheritance

# Define list of server names to query
$servers = @(
    "SERVER01",
    "SERVER02",
    "SERVER03"
)

# Process each server in the list
$results = foreach ($server in $servers) {
    Write-Host "Processing $server..." -ForegroundColor Cyan
    
    try {
        # Retrieve the computer object from Active Directory with required properties
        $computer = Get-ADComputer -Identity $server -Properties DistinguishedName, CanonicalName
        
        if ($computer) {
            # Extract the OU path by removing the computer's CN (Common Name) from the DN
            # Example: CN=SERVER01,OU=Servers,DC=domain,DC=com becomes OU=Servers,DC=domain,DC=com
            $ou = $computer.DistinguishedName -replace '^CN=.*?(?<!\\),'
            
            # Initialize array to store GPO information
            $gpos = @()
            $currentPath = $ou
            
            # Walk up the OU hierarchy from the computer's location to the domain root
            while ($currentPath) {
                try {
                    # Get all GPOs linked to the current container/OU
                    $linkedGPOs = Get-GPInheritance -Target $currentPath -ErrorAction SilentlyContinue
                    
                    if ($linkedGPOs) {
                        # Process each GPO link at this level
                        foreach ($gpo in $linkedGPOs.GpoLinks) {
                            # Only include GPOs that are enabled
                            if ($gpo.Enabled -eq $true) {
                                # Create custom object with GPO details
                                $gpos += [PSCustomObject]@{
                                    Server = $server
                                    GPOName = $gpo.DisplayName
                                    GPOEnabled = $gpo.Enabled
                                    LinkEnabled = $gpo.Enabled
                                    Enforced = $gpo.Enforced        # "No Override" setting
                                    Order = $gpo.Order              # Processing order (lower = higher priority)
                                    Target = $currentPath           # Where the GPO is linked
                                }
                            }
                        }
                    }
                } catch {
                    # Silently continue if we can't read GPO inheritance at this level
                }
                
                # Move to the parent container in the hierarchy
                if ($currentPath -match ',') {
                    $currentPath = $currentPath -replace '^[^,]+,'
                } else {
                    # Reached the top of the hierarchy
                    $currentPath = $null
                }
            }
            
            # Return the GPOs found for this server
            $gpos
        }
    } catch {
        Write-Warning "Failed to process $server : $_"
    }
}

# Display results in a formatted table
$results | Format-Table -AutoSize

# Optional: Export results to CSV file for further analysis
# $results | Export-Csv -Path "C:\Temp\ServerGPOs.csv" -NoTypeInformation
