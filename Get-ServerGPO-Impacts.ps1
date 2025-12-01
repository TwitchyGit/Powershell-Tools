<#
.SYNOPSIS
    Gets all Group Policy Objects (GPOs) that apply to specified computer objects across multiple AD domains.
.DESCRIPTION
    This script queries Active Directory to find computer objects across different domains and determines 
    which GPOs apply to them based on their OU location. It walks up the OU hierarchy to discover all
    linked GPOs, including their enabled status, enforcement, and link order.
    
    Displays summary tables by AppHost and detailed GPO listings.
    
    Note: This shows GPOs that SHOULD apply based on AD structure. It does not query the
    actual resultant set of policy (RSoP) from live machines.
.NOTES
    Requires: Active Directory and Group Policy PowerShell modules
    Must have appropriate permissions to query each domain
#>

# Import only required commands to minimize module load time and memory footprint
Import-Module ActiveDirectory -Cmdlet Get-ADComputer
Import-Module GroupPolicy -Cmdlet Get-GPInheritance

# Define server list organized by AppHost
$servers = @{
    'PVWA'  = @("UK\server1", "USA\server2")
    'CPM'   = @("IRELAND\server14", "USA\server2234")
    'PSM'   = @("SCOTLAND\server1", "USA\server2")
}

# Process each AppHost and its servers
$results = foreach ($appHost in $servers.Keys) {
    Write-Host "`nProcessing AppHost: $appHost" -ForegroundColor Magenta
    
    foreach ($serverEntry in $servers[$appHost]) {
        # Split domain and server name
        $domain, $serverName = $serverEntry -split '\\'
        
        Write-Host "  Processing $domain\$serverName..." -ForegroundColor Cyan
        
        try {
            # Retrieve the computer object from the specified domain
            $computer = Get-ADComputer -Identity $serverName -Server $domain -Properties DistinguishedName, CanonicalName -ErrorAction Stop
            
            if ($computer) {
                # Extract the OU path by removing the computer's CN (Common Name) from the DN
                $ou = $computer.DistinguishedName -replace '^CN=.*?(?<!\\),'
                
                # Initialize array to store GPO information
                $gpos = @()
                $currentPath = $ou
                
                # Walk up the OU hierarchy from the computer's location to the domain root
                while ($currentPath) {
                    try {
                        # Get all GPOs linked to the current container/OU in the specific domain
                        $linkedGPOs = Get-GPInheritance -Target $currentPath -Domain $domain -ErrorAction SilentlyContinue
                        
                        if ($linkedGPOs) {
                            # Process each GPO link at this level
                            foreach ($gpo in $linkedGPOs.GpoLinks) {
                                # Only include GPOs that are enabled
                                if ($gpo.Enabled -eq $true) {
                                    # Create custom object with GPO details
                                    $gpos += [PSCustomObject]@{
                                        AppHost = $appHost
                                        Domain = $domain
                                        Server = $serverName
                                        FullName = "$domain\$serverName"
                                        GPOName = $gpo.DisplayName
                                        GPOEnabled = $gpo.Enabled
                                        LinkEnabled = $gpo.Enabled
                                        Enforced = $gpo.Enforced
                                        Order = $gpo.Order
                                        Target = $currentPath
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
                        $currentPath = $null
                    }
                }
                
                # Return the GPOs found for this server
                $gpos
            }
        } catch {
            Write-Warning "Failed to process $domain\$serverName : $_"
        }
    }
}

# ============================================================================
# GENERATE SUMMARY BY APPHOST
# ============================================================================
# This section creates detailed summaries for each AppHost showing:
# - Individual server GPO counts
# - OU locations
# - Enforced GPO counts
# - Totals per AppHost

Write-Output "`n================ GPO SUMMARY BY APPHOST ================"

foreach ($appHost in ($servers.Keys | Sort-Object)) {
    # Filter results to only this AppHost
    $appHostResults = $results | Where-Object { $_.AppHost -eq $appHost }
    
    if ($appHostResults) {
        Write-Output "`n$appHost Servers:"
        
        # Group by server and calculate statistics for each
        $appHostSummary = $appHostResults | Group-Object FullName | Select-Object @{
            Name = 'Server'
            Expression = { $_.Name }
        }, @{
            Name = 'Total GPOs'
            Expression = { $_.Count }
        }, @{
            Name = 'Enforced'
            Expression = { ($_.Group | Where-Object { $_.Enforced -eq $true }).Count }
        }, @{
            Name = 'OU Location'
            Expression = { 
                # Get the most specific OU path for this server
                $firstTarget = ($_.Group | Select-Object -First 1).Target
                # Convert DN format to readable format (OU hierarchy)
                if ($firstTarget -match 'OU=') {
                    ($firstTarget -replace '^OU=' -replace ',OU=', ' > ' -replace ',DC=.*

# Optional: Export results to CSV files
# $results | Export-Csv -Path "C:\Temp\ServerGPO_Details.csv" -NoTypeInformation
# $overallSummary | Export-Csv -Path "C:\Temp\AppHost_Summary.csv" -NoTypeInformation, '')
                } else {
                    'Domain Root'
                }
            }
        }
        
        $appHostSummary | Format-Table -AutoSize
        
        # Calculate and display AppHost-level totals
        $totalGPOs = ($appHostResults | Measure-Object).Count
        $totalEnforced = ($appHostResults | Where-Object { $_.Enforced -eq $true } | Measure-Object).Count
        Write-Output "  $appHost Totals: $totalGPOs GPOs ($totalEnforced Enforced)"
    }
}

# ============================================================================
# OVERALL SUMMARY BY APPHOST
# ============================================================================
# This section creates a high-level comparison table across all AppHosts
# Shows: server count, total GPOs, average GPOs per server, and enforced counts

Write-Output "`n============== OVERALL SUMMARY BY APPHOST =============="

$overallSummary = $results | Group-Object AppHost | Select-Object @{
    Name = 'AppHost'
    Expression = { $_.Name }
}, @{
    Name = 'Servers'
    Expression = { ($_.Group | Select-Object -Unique FullName).Count }
}, @{
    Name = 'Total GPOs'
    Expression = { $_.Count }
}, @{
    Name = 'Avg GPOs/Server'
    Expression = { [math]::Round($_.Count / ($_.Group | Select-Object -Unique FullName).Count, 1) }
}, @{
    Name = 'Enforced GPOs'
    Expression = { ($_.Group | Where-Object { $_.Enforced -eq $true }).Count }
}

$overallSummary | Format-Table -AutoSize

# ============================================================================
# DETAILED GPO LIST
# ============================================================================
# This section shows every GPO assignment with full details
# Sorted by AppHost, then Server, then GPO order for easy review

Write-Output "`n============== DETAILED GPO LIST BY APPHOST ============="
$results | Sort-Object AppHost, FullName, Order | Format-Table AppHost, FullName, GPOName, Enforced, Order, Target -AutoSize

# ============================================================================
# GRAND TOTALS
# ============================================================================
# Final summary showing overall statistics across all AppHosts and domains

Write-Output "`n===================== GRAND TOTALS ====================="
Write-Output "Total AppHosts: $($servers.Keys.Count)"
Write-Output "Total Servers: $(($results | Select-Object -Unique FullName).Count)"
Write-Output "Total GPO Assignments: $($results.Count)"
Write-Output "Total Enforced GPOs: $(($results | Where-Object { $_.Enforced -eq $true }).Count)"
Write-Output "========================================================`n"

# Optional: Export results to CSV files
# $results | Export-Csv -Path "C:\Temp\ServerGPO_Details.csv" -NoTypeInformation
# $overallSummary | Export-Csv -Path "C:\Temp\AppHost_Summary.csv" -NoTypeInformation
