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

# Collect all unique file paths across all locations
$allFilePaths = @{}

# Get files from golden source
if (Test-Path $goldenSourcePath) {
    Get-ChildItem -Path $goldenSourcePath -File -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($goldenSourcePath.Length).TrimStart('\')
        if (-not $allFilePaths.ContainsKey($relativePath)) {
            $allFilePaths[$relativePath] = $true
        }
    }
}

# Get files from all source folders
foreach ($folder in $sourceFolders) {
    if (Test-Path $folder) {
        Get-ChildItem -Path $folder -File -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Substring($folder.Length).TrimStart('\')
            if (-not $allFilePaths.ContainsKey($relativePath)) {
                $allFilePaths[$relativePath] = $true
            }
        }
    }
}

# Process each unique file
$report = @()
foreach ($relativePath in $allFilePaths.Keys) {
    
    # Check golden source
    $goldenFullPath = Join-Path $goldenSourcePath $relativePath
    $goldenExists = Test-Path $goldenFullPath
    $goldenDate = if ($goldenExists) { (Get-Item $goldenFullPath).LastWriteTime } else { $null }
    
    # Check each source folder
    $sourceVersions = @()
    foreach ($folder in $sourceFolders) {
        $sourceFullPath = Join-Path $folder $relativePath
        $folderName = Split-Path $folder -Leaf
        
        if (Test-Path $sourceFullPath) {
            $sourceDate = (Get-Item $sourceFullPath).LastWriteTime
            $sourceVersions += @{
                FolderName = $folderName
                FullPath = $sourceFullPath
                LastWriteTime = $sourceDate
            }
        }
    }
    
    # Find which folders have the file and which don't
    $foundIn = ($sourceVersions | ForEach-Object { $_.FolderName }) -join ", "
    $missingFolders = $sourceFolders | Where-Object {
        $folderName = Split-Path $_ -Leaf
        $folderName -notin ($sourceVersions | ForEach-Object { $_.FolderName })
    } | ForEach-Object { Split-Path $_ -Leaf }
    $missingIn = if ($missingFolders) { $missingFolders -join ", " } else { "None" }
    
    # Find the latest version
    $latest = $sourceVersions | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    
    # Check if all match
    $allDates = @()
    if ($goldenExists) { $allDates += $goldenDate }
    $allDates += $sourceVersions | ForEach-Object { $_.LastWriteTime }
    $uniqueDates = $allDates | Select-Object -Unique
    $allMatch = ($uniqueDates.Count -eq 1) -and ($sourceVersions.Count -eq $sourceFolders.Count) -and $goldenExists
    
    # Determine action
    $action = if (-not $goldenExists) {
        "New"
    } elseif ($latest -and $goldenDate -lt $latest.LastWriteTime) {
        "Updated"
    } else {
        "No Change"
    }
    
    # Build differences
    $differences = @()
    if ($goldenExists) {
        $differences += "Golden: $goldenDate"
    } else {
        $differences += "Golden: Missing"
    }
    foreach ($sv in $sourceVersions) {
        $differences += "$($sv.FolderName): $($sv.LastWriteTime)"
    }
    foreach ($mf in $missingFolders) {
        $differences += "$mf: Missing"
    }
    $differencesText = if ($allMatch) { "All Match" } else { $differences -join " | " }
    
    # Copy file if needed
    if ($action -ne "No Change" -and $latest) {
        $destinationDir = Split-Path $goldenFullPath -Parent
        if (-not (Test-Path $destinationDir)) {
            New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $latest.FullPath -Destination $goldenFullPath -Force
    }
    
    $report += [PSCustomObject]@{
        FileName = $relativePath
        GoldenExists = $goldenExists
        Action = $action
        AllMatch = $allMatch
        FoundIn = if ($foundIn) { $foundIn } else { "None" }
        MissingIn = $missingIn
        LatestInFolder = if ($latest) { $latest.FolderName } else { "N/A" }
        LatestDate = if ($latest) { $latest.LastWriteTime } else { $null }
        Status = $differencesText
    }
}

# Display report
$report | Format-Table -AutoSize

# Export report to CSV
$reportPath = Join-Path $goldenSourcePath "consolidation_report.csv"
$report | Export-Csv -Path $reportPath -NoTypeInformation

Write-Host "`nReport saved to: $reportPath"
Write-Host "Total unique files: $($report.Count)"
