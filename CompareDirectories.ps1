# Golden Source File Comparison
# Compares files in GoldenSource against comparison folders (read-only report)

param(
    [Parameter(Mandatory=$true)]
    [string]$GoldenSource,
    
    [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
    [string[]]$CompareFolders
)

# Report 1: Files in GoldenSource
$goldenReport = @()
if (Test-Path $GoldenSource) {
    $goldenFiles = Get-ChildItem -Path $GoldenSource -File -Recurse
    
    foreach ($goldenFile in $goldenFiles) {
        $relativePath = $goldenFile.FullName.Substring($GoldenSource.Length).TrimStart('\')
        $goldenDate = $goldenFile.LastWriteTime
        
        # Check each compare folder for this file
        $newerIn = ""
        $latestDate = $goldenDate
        $latestFolder = ""
        
        foreach ($folder in $CompareFolders) {
            $compareFullPath = Join-Path $folder $relativePath
            
            if (Test-Path $compareFullPath) {
                $compareDate = (Get-Item $compareFullPath).LastWriteTime
                
                if ($compareDate -gt $latestDate) {
                    $latestDate = $compareDate
                    $latestFolder = Split-Path $folder -Leaf
                }
            }
        }
        
        $newerIn = if ($latestFolder) { "Newer in $latestFolder" } else { "" }
        
        $goldenReport += [PSCustomObject]@{
            FileName = $relativePath
            GoldenDate = $goldenDate
            Status = $newerIn
        }
    }
}

# Report 2: Files NOT in GoldenSource but in CompareFolders
$missingReport = @()
$filesInCompareFolders = @{}

foreach ($folder in $CompareFolders) {
    if (Test-Path $folder) {
        Get-ChildItem -Path $folder -File -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Substring($folder.Length).TrimStart('\')
            
            # Check if this file exists in GoldenSource
            $goldenPath = Join-Path $GoldenSource $relativePath
            if (-not (Test-Path $goldenPath)) {
                
                # Track this file
                if (-not $filesInCompareFolders.ContainsKey($relativePath)) {
                    $filesInCompareFolders[$relativePath] = @()
                }
                
                $filesInCompareFolders[$relativePath] += @{
                    FolderName = Split-Path $folder -Leaf
                    LastWriteTime = $_.LastWriteTime
                }
            }
        }
    }
}

# Find the newest version of each missing file
foreach ($fileName in $filesInCompareFolders.Keys) {
    $versions = $filesInCompareFolders[$fileName]
    $newest = $versions | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    
    $missingReport += [PSCustomObject]@{
        FileName = $fileName
        NewestIn = $newest.FolderName
        Date = $newest.LastWriteTime
    }
}

# Display reports
Write-Output "`n=== FILES IN GOLDEN SOURCE ==="
$goldenReport | Format-Table -AutoSize

Write-Output "`n=== FILES NOT IN GOLDEN SOURCE ==="
$missingReport | Format-Table -AutoSize

# Export reports to CSV
$reportPath1 = Join-Path (Get-Location) "golden_source_comparison.csv"
$reportPath2 = Join-Path (Get-Location) "files_not_in_golden.csv"

$goldenReport | Export-Csv -Path $reportPath1 -NoTypeInformation
$missingReport | Export-Csv -Path $reportPath2 -NoTypeInformation

Write-Output "`nReports saved to:"
Write-Output "  $reportPath1"
Write-Output "  $reportPath2"
