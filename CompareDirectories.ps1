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

# Collect all files from source folders
$allFiles = @{}
foreach ($folder in $sourceFolders) {
    if (Test-Path $folder) {
        Get-ChildItem -Path $folder -File -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Substring($folder.Length).TrimStart('\')
            
            if (-not $allFiles.ContainsKey($relativePath)) {
                $allFiles[$relativePath] = @()
            }
            
            $allFiles[$relativePath] += @{
                FullPath = $_.FullName
                LastWriteTime = $_.LastWriteTime
                SourceFolder = $folder
            }
        }
    }
}

# Process files and build report
$report = @()
foreach ($fileName in $allFiles.Keys) {
    $fileVersions = $allFiles[$fileName]
    $latest = $fileVersions | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    
    $destinationPath = Join-Path $goldenSourcePath $fileName
    $destinationDir = Split-Path $destinationPath -Parent
    
    if (-not (Test-Path $destinationDir)) {
        New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
    }
    
    $action = "New"
    $goldenExists = Test-Path $destinationPath
    
    if ($goldenExists) {
        $goldenFile = Get-Item $destinationPath
        if ($goldenFile.LastWriteTime -lt $latest.LastWriteTime) {
            $action = "Updated"
        } else {
            $action = "No Change"
        }
    }
    
    $missingInGolden = -not $goldenExists
    
    if ($action -ne "No Change") {
        Copy-Item -Path $latest.FullPath -Destination $destinationPath -Force
    }
    
    # Check if all versions have the same timestamp
    $allTimestamps = $fileVersions | ForEach-Object { $_.LastWriteTime }
    $uniqueTimestamps = $allTimestamps | Select-Object -Unique
    $allMatch = $uniqueTimestamps.Count -eq 1
    
    # Build list of all source folders containing this file
    $allSourceFolders = ($fileVersions | ForEach-Object { Split-Path $_.SourceFolder -Leaf }) -join ", "
    
    # Build differences summary
    $differences = if ($allMatch) {
        "All Match"
    } else {
        $fileVersions | ForEach-Object {
            $folderName = Split-Path $_.SourceFolder -Leaf
            "$folderName ($($_.LastWriteTime))"
        } | ForEach-Object { $_ -join "; " }
        $differences -join "; "
    }
    
    $report += [PSCustomObject]@{
        FileName = $fileName
        Action = $action
        FoundIn = $allSourceFolders
        VersionCount = $fileVersions.Count
        AllMatch = $allMatch
        Differences = $differences
        SelectedFrom = Split-Path $latest.SourceFolder -Leaf
        SelectedDate = $latest.LastWriteTime
        MissingInGolden = $missingInGolden
    }
}

# Display report
$report | Format-Table -AutoSize

# Export report to CSV
$reportPath = Join-Path $goldenSourcePath "consolidation_report.csv"
$report | Export-Csv -Path $reportPath -NoTypeInformation

Write-Host "`nReport saved to: $reportPath"
Write-Host "Total files processed: $($report.Count)"
