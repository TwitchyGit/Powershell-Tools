# Golden Source File Consolidator
# Compares files in GoldenSource against all source folders

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

# Get all files from golden source only
$goldenFiles = @()
if (Test-Path $goldenSourcePath) {
    $goldenFiles = Get-ChildItem -Path $goldenSourcePath -File -Recurse
}

# Process each file in golden source
$report = @()
foreach ($goldenFile in $goldenFiles) {
    $relativePath = $goldenFile.FullName.Substring($goldenSourcePath.Length).TrimStart('\')
    $goldenDate = $goldenFile.LastWriteTime
    
    # Check each source folder for this file
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
    
    # Find the latest version from source folders
    $latest = $sourceVersions | Sort-Object -Property LastWriteTime -Descending | Select-Object -First 1
    
    # Check if all match
    $allDates = @($goldenDate)
    $allDates += $sourceVersions | ForEach-Object { $_.LastWriteTime }
    $uniqueDates = $allDates | Select-Object -Unique
    $allMatch = ($uniqueDates.Count -eq 1) -and ($sourceVersions.Count -eq $sourceFolders.Count)
    
    # Determine action
    $action = if ($latest -and $goldenDate -lt $latest.LastWriteTime) {
        "Updated"
    } else {
        "No Change"
    }
    
    # Build differences
    $differences = @("Golden: $goldenDate")
    foreach ($sv in $sourceVersions) {
        $differences += "$($sv.FolderName): $($sv.LastWriteTime)"
    }
    foreach ($mf in $missingFolders) {
        $differences += "${mf}: Missing"
    }
    $differencesText = if ($allMatch) { "All Match" } else { $differences -join " | " }
    
    # Copy file if needed
    if ($action -eq "Updated" -and $latest) {
        Copy-Item -Path $latest.FullPath -Destination $goldenFile.FullName -Force
    }
    
    $report += [PSCustomObject]@{
        FileName = $relativePath
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

# Export report to CSV in the current directory
$reportPath = Join-Path (Get-Location) "consolidation_report.csv"
$report | Export-Csv -Path $reportPath -NoTypeInformation

Write-Output "`nReport saved to: $reportPath"
Write-Output "Total files in GoldenSource: $($report.Count)"
