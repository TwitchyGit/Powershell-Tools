<#
.SYNOPSIS
    Scans Active Directory domains for OUs containing computer objects and tracks changes.

.DESCRIPTION
    This script scans multiple AD domains, identifies all OUs with computer objects,
    and compares results with the previous scan to detect changes.

.PARAMETER Domains
    Array of domain names to scan. If not specified, uses current domain.

.PARAMETER OutputPath
    Path where scan results are stored. Default: C:\ADScans

.EXAMPLE
    .\AD-ComputerOU-Scanner.ps1 -Domains "domain1.com","domain2.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string[]]$Domains,
    
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "C:\ADScans"
)

# Helper function for consistent logging
function Write-Log {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter(Mandatory=$false)]
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Header')]
        [string]$Level = 'Info'
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    switch ($Level) {
        'Info'    { Write-Host "[$timestamp] [INFO] $Message" -ForegroundColor Cyan }
        'Success' { Write-Host "[$timestamp] [SUCCESS] $Message" -ForegroundColor Green }
        'Warning' { Write-Host "[$timestamp] [WARNING] $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "[$timestamp] [ERROR] $Message" -ForegroundColor Red }
        'Header'  { Write-Host "`n========================================" -ForegroundColor Magenta
                    Write-Host "$Message" -ForegroundColor Magenta
                    Write-Host "========================================" -ForegroundColor Magenta }
    }
}

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Log "Created output directory: $OutputPath" -Level Success
}

# Function to get current domain if none specified
function Get-CurrentDomain {
    try {
        return [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
    } catch {
        Write-Log "Failed to get current domain: $_" -Level Error
        return $null
    }
}

# Function to scan a single domain
function Scan-DomainOUs {
    param(
        [string]$DomainName
    )
    
    Write-Log "Scanning Domain: $DomainName" -Level Header
    
    $results = @()
    $allOUs = @()
    
    # Get all OUs in the domain
    try {
        $allOUs = Get-ADOrganizationalUnit -Filter * -Server $DomainName -Properties DistinguishedName -ErrorAction Stop | 
                  Select-Object -ExpandProperty DistinguishedName
    } catch {
        Write-Log "Failed to retrieve OUs from domain $DomainName : $_" -Level Error
        return $results
    }
    
    # Get domain root
    try {
        $domainRoot = (Get-ADDomain -Server $DomainName -ErrorAction Stop).DistinguishedName
        $allOUs += $domainRoot
    } catch {
        Write-Log "Failed to get domain root for $DomainName : $_" -Level Warning
    }
    
    if ($allOUs.Count -eq 0) {
        Write-Log "No OUs found in domain $DomainName" -Level Warning
        return $results
    }
    
    Write-Log "Found $($allOUs.Count) OUs (including domain root)" -Level Info
    Write-Log "Checking for computer objects..." -Level Info
    
    $counter = 0
    foreach ($ou in $allOUs) {
        $counter++
        Write-Progress -Activity "Scanning OUs in $DomainName" -Status "Processing OU $counter of $($allOUs.Count)" -PercentComplete (($counter / $allOUs.Count) * 100)
        
        # Get computers in this OU (not in sub-OUs)
        try {
            $computers = Get-ADComputer -Filter * -SearchBase $ou -SearchScope OneLevel -Server $DomainName -ErrorAction Stop
            
            if ($computers) {
                $computerCount = ($computers | Measure-Object).Count
                
                try {
                    $computerNames = ($computers | Select-Object -ExpandProperty Name | Sort-Object) -join ';'
                } catch {
                    Write-Log "Failed to get computer names for OU: $ou" -Level Warning
                    $computerNames = "Error retrieving names"
                }
                
                $ouInfo = [PSCustomObject]@{
                    Domain = $DomainName
                    OU = $ou
                    ComputerCount = $computerCount
                    ComputerNames = $computerNames
                    ScanTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                }
                
                $results += $ouInfo
                Write-Log "Found OU: $ou - $computerCount computer(s)" -Level Success
            }
        } catch {
            Write-Log "Failed to query computers in OU: $ou - $_" -Level Warning
            continue
        }
    }
    
    Write-Progress -Activity "Scanning OUs in $DomainName" -Completed
    
    return $results
}

# Function to compare scan results
function Compare-ScanResults {
    param(
        [array]$CurrentScan,
        [array]$PreviousScan
    )
    
    $changes = @{
        NewOUs = @()
        RemovedOUs = @()
        ModifiedOUs = @()
    }
    
    # Create hashtables for easier comparison
    $currentHash = @{}
    $previousHash = @{}
    
    foreach ($item in $CurrentScan) {
        $key = "$($item.Domain)|$($item.OU)"
        $currentHash[$key] = $item
    }
    
    foreach ($item in $PreviousScan) {
        $key = "$($item.Domain)|$($item.OU)"
        $previousHash[$key] = $item
    }
    
    # Find new OUs
    foreach ($key in $currentHash.Keys) {
        if (-not $previousHash.ContainsKey($key)) {
            $changes.NewOUs += $currentHash[$key]
        }
    }
    
    # Find removed OUs
    foreach ($key in $previousHash.Keys) {
        if (-not $currentHash.ContainsKey($key)) {
            $changes.RemovedOUs += $previousHash[$key]
        }
    }
    
    # Find modified OUs (computer count or names changed)
    foreach ($key in $currentHash.Keys) {
        if ($previousHash.ContainsKey($key)) {
            $current = $currentHash[$key]
            $previous = $previousHash[$key]
            
            if (($current.ComputerCount -ne $previous.ComputerCount) -or 
                ($current.ComputerNames -ne $previous.ComputerNames)) {
                
                $changeInfo = [PSCustomObject]@{
                    Domain = $current.Domain
                    OU = $current.OU
                    PreviousCount = $previous.ComputerCount
                    CurrentCount = $current.ComputerCount
                    CountDelta = $current.ComputerCount - $previous.ComputerCount
                    PreviousComputers = $previous.ComputerNames
                    CurrentComputers = $current.ComputerNames
                }
                
                $changes.ModifiedOUs += $changeInfo
            }
        }
    }
    
    return $changes
}

# Function to display changes
function Show-Changes {
    param($Changes, $PreviousScanTime)
    
    Write-Log "CHANGE DETECTION REPORT - Previous Scan: $PreviousScanTime" -Level Header
    
    $hasChanges = $false
    
    if ($Changes.NewOUs.Count -gt 0) {
        $hasChanges = $true
        Write-Log "NEW OUs WITH COMPUTERS - $($Changes.NewOUs.Count) found" -Level Success
        foreach ($ou in $Changes.NewOUs) {
            Write-Log "  [+] Domain: $($ou.Domain)" -Level Success
            Write-Log "      OU: $($ou.OU)" -Level Success
            Write-Log "      Computers: $($ou.ComputerCount)" -Level Success
        }
    }
    
    if ($Changes.RemovedOUs.Count -gt 0) {
        $hasChanges = $true
        Write-Log "REMOVED OUs - $($Changes.RemovedOUs.Count) no longer contain computers" -Level Error
        foreach ($ou in $Changes.RemovedOUs) {
            Write-Log "  [-] Domain: $($ou.Domain)" -Level Error
            Write-Log "      OU: $($ou.OU)" -Level Error
            Write-Log "      Previous Count: $($ou.ComputerCount)" -Level Error
        }
    }
    
    if ($Changes.ModifiedOUs.Count -gt 0) {
        $hasChanges = $true
        Write-Log "MODIFIED OUs - $($Changes.ModifiedOUs.Count) changed" -Level Warning
        foreach ($ou in $Changes.ModifiedOUs) {
            Write-Log "  [~] Domain: $($ou.Domain)" -Level Warning
            Write-Log "      OU: $($ou.OU)" -Level Warning
            Write-Log "      Computer Count: $($ou.PreviousCount) -> $($ou.CurrentCount) (Delta: $($ou.CountDelta))" -Level Warning
            
            # Show added/removed computers
            try {
                $prevComputers = $ou.PreviousComputers -split ';'
                $currComputers = $ou.CurrentComputers -split ';'
                
                $added = $currComputers | Where-Object { $_ -notin $prevComputers }
                $removed = $prevComputers | Where-Object { $_ -notin $currComputers }
                
                if ($added) {
                    Write-Log "      Added: $($added -join ', ')" -Level Success
                }
                if ($removed) {
                    Write-Log "      Removed: $($removed -join ', ')" -Level Error
                }
            } catch {
                Write-Log "Failed to calculate computer differences for OU: $($ou.OU)" -Level Warning
            }
        }
    }
    
    if (-not $hasChanges) {
        Write-Log "No changes detected since last scan." -Level Success
    }
}

# Main script execution
Write-Log "AD Computer OU Scanner - Started" -Level Header
Write-Log "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info

# If no domains specified, use current domain
if (-not $Domains) {
    $currentDomain = Get-CurrentDomain
    if ($currentDomain) {
        $Domains = @($currentDomain)
        Write-Log "No domains specified. Using current domain: $currentDomain" -Level Info
    } else {
        Write-Log "Could not determine current domain and no domains specified." -Level Error
        exit 1
    }
}

# Load previous scan if exists
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$currentScanFile = Join-Path $OutputPath "ADScan_$timestamp.csv"
$latestScanFile = Join-Path $OutputPath "ADScan_Latest.csv"
$previousScan = $null
$previousScanTime = $null

if (Test-Path $latestScanFile) {
    Write-Log "Previous scan found. Loading for comparison..." -Level Info
    try {
        $previousScan = Import-Csv $latestScanFile -ErrorAction Stop
        $previousScanTime = (Get-Item $latestScanFile).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    } catch {
        Write-Log "Failed to load previous scan file: $_" -Level Warning
        $previousScan = $null
    }
}

# Scan all domains
$allResults = @()
foreach ($domain in $Domains) {
    try {
        $domainResults = Scan-DomainOUs -DomainName $domain
        $allResults += $domainResults
    } catch {
        Write-Log "Critical error scanning domain $domain : $_" -Level Error
        continue
    }
}

# Save current scan
try {
    $allResults | Export-Csv -Path $currentScanFile -NoTypeInformation -ErrorAction Stop
    Write-Log "Current scan saved to: $currentScanFile" -Level Success
} catch {
    Write-Log "Failed to save current scan file: $_" -Level Error
}

try {
    $allResults | Export-Csv -Path $latestScanFile -NoTypeInformation -Force -ErrorAction Stop
    Write-Log "Latest scan updated: $latestScanFile" -Level Success
} catch {
    Write-Log "Failed to save latest scan file: $_" -Level Error
}

Write-Log "SCAN SUMMARY" -Level Header
Write-Log "Total OUs with computers: $($allResults.Count)" -Level Success
Write-Log "Total computers found: $(($allResults | Measure-Object -Property ComputerCount -Sum).Sum)" -Level Success
Write-Log "Results saved to: $currentScanFile" -Level Success

# Compare with previous scan if available
if ($previousScan) {
    try {
        $changes = Compare-ScanResults -CurrentScan $allResults -PreviousScan $previousScan
        Show-Changes -Changes $changes -PreviousScanTime $previousScanTime
        
        # Save change report
        $changeReportFile = Join-Path $OutputPath "ChangeReport_$timestamp.txt"
        try {
            Show-Changes -Changes $changes -PreviousScanTime $previousScanTime | Out-File $changeReportFile -ErrorAction Stop
            Write-Log "Change report saved to: $changeReportFile" -Level Success
        } catch {
            Write-Log "Failed to save change report: $_" -Level Warning
        }
    } catch {
        Write-Log "Failed to compare scan results: $_" -Level Error
    }
} else {
    Write-Log "This is the first scan. No comparison available." -Level Info
    Write-Log "Run the script again to detect changes." -Level Info
}

Write-Log "Scan Complete!" -Level Header
