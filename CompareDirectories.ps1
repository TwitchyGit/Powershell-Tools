# Golden Source File Consolidator
# Consolidates the latest version of files from multiple source folders

param(
    [Parameter(Mandatory=$true)]
    [string]$GoldenSourcePath,
    
    [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
    [string[]]$SourceFolders
)

$goldenSourcePath = $GoldenSourcePath
$sourceFolders = $SourceFolders

# Create golden source folder if it doesn't exist
if (-not (Test-Path $goldenSourcePath)) {
    New-Item -Path $goldenSourcePath -ItemType Directory | Out-Null
}

# Collect all files from golden source and source folders
$allFiles = @{}

# First, collect files from golden source
if (Test-Path $goldenSourcePath) {
    Get-ChildItem -Path $goldenSourcePath -File -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($goldenSourcePath.Length).TrimStart('\')
        
        if (-not $allFiles.ContainsKey($relativePath)) {
            $allFiles[$relativePath] = @{
                Golden = $null
                Sources = @()
            }
        }
        
        $allFiles[$relativePath].Golden = @{
            FullPath = $_.FullName
            LastWriteTime = $_.LastWriteTime
            Exists = $true
        }
    }
}

# Then collect files from source folders
foreach ($folder in $sourceFolders) {
    if (Test-Path $folder) {
        Get-ChildItem -Path $folder -File -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Substring($folder.Length).TrimStart('\')
            
            if (-not $allFiles.ContainsKey($relativePath)) {
                $allFiles[$relativePath] = @{
                    Golden = @{ Exists = $false }
                    Sources = @()
                }
            }
            
            $allFiles[$relativePath].Sources += @{
                FullPath = $_.FullName
                LastWriteTime = $_.LastWriteTime
                SourceFolder = $folder
                FolderName = Split-Path $folder -Leaf
            }
        }
    }
}

# Process files and build report
$report = @()
foreach ($fileName in $allFiles.Keys) {
    $fileInfo = $allFiles[$fileName]
    $goldenFile = $fileInfo.Golden
    $sourceFiles = $fileInfo.Sources
    
    $destinationPath = Join-Path $goldenSourcePath $fileName
    $destinationDir = Split-Path $destinationPath -Parent
    
    if (-not (Test-Path $destinationDir)) {
        New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
    }
    
    # Find the latest version across all sources
    $latest = $sourceFiles | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    
    # Check which folders have this file
    $foundInFolders = ($sourceFiles | ForEach-Object { $_.FolderName }) -join ", "
    $missingInFolders = $sourceFolders | Where-Object {
        $folderName = Split-Path $_ -Leaf
        $folderName -notin ($sourceFiles | ForEach-Object { $_.FolderName })
    } | ForEach-Object { Split-Path $_ -Leaf }
    $missingIn = if ($missingInFolders) { $missingInFolders -join ", " } else { "None" }
    
    # Check if all versions match (including golden source if it exists)
    $allTimestamps = @()
    if ($goldenFile.Exists) {
        $allTimestamps += $goldenFile.LastWriteTime
    }
    $allTimestamps += $sourceFiles | ForEach-Object { $_.LastWriteTime }
    $uniqueTimestamps = $allTimestamps | Select-Object -Unique
    $allMatch = ($uniqueTimestamps.Count -eq 1) -and ($sourceFiles.Count -eq $sourceFolders.Count) -and $goldenFile.Exists
    
    # Determine action
    $action = "No Change"
    if (-not $goldenFile.Exists) {
        $action = "New"
    } elseif ($latest -and $goldenFile.LastWriteTime -lt $latest.LastWriteTime) {
        $action = "Updated"
    }
    
    # Build differences summary
    $differences = @()
    if ($goldenFile.Exists) {
        $differences += "Golden ($($goldenFile.LastWriteTime))"
    } else {
        $differences += "Golden (Missing)"
    }
    
    foreach ($sf in $sourceFiles) {
        $differences += "$($sf.FolderName) ($($sf.LastWriteTime))"
    }
    
    $differencesText = if ($allMatch) { "All Match" } else { $differences -join "; " }
    
    # Copy file if needed
    if ($action -ne "No Change") {
        Copy-Item -Path $latest.FullPath -Destination $destinationPath -Force
    }
    
    $report += [PSCustomObject]@{
        FileName = $fileName
        GoldenExists = $goldenFile.Exists
        Action = $action
        AllMatch = $allMatch
        FoundIn = $foundInFolders
        MissingIn = $missingIn
        LatestInFolder = if ($latest) { $latest.FolderName } else { "N/A" }
        LatestDate = if ($latest) { $latest.LastWriteTime } else { $null }
        Differences = $differencesText
    }
}

# Display report
$report | Format-Table -AutoSize

# Export report to CSV
$reportPath = Join-Path $goldenSourcePath "consolidation_report.csv"
$report | Export-Csv -Path $reportPath -NoTypeInformation

Write-Host "`nReport saved to: $reportPath"
Write-Host "Total files processed: $($report.Count)"
