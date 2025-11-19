# Golden Source File Comparison
# Consolidates the latest version of files from multiple source folders

param(
    [Parameter(Mandatory=$true)] [string]$GoldenSourcePath,
    [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)] [string[]]$SourceFolders
)

$goldenSourcePath = $GoldenSourcePath
$sourceFolders = $SourceFolders

# Create golden source folder if it doesn't exist
if (-not (Test-Path $goldenSourcePath)) {
    Write-Output "ERROR: $goldenSourcePath does not exist"
    exit 1
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
    
    Copy-Item -Path $latest.FullPath -Destination $destinationPath -Force
    
    $report += [PSCustomObject]@{
        FileName = $fileName
        SourceFolder = $latest.SourceFolder
        LastModified = $latest.LastWriteTime
        VersionCount = $fileVersions.Count
        CopiedTo = $destinationPath
    }
}

# Display report
$report | Format-Table -AutoSize

# Export report to CSV
$reportPath = Join-Path $goldenSourcePath "consolidation_report.csv"
$report | Export-Csv -Path $reportPath -NoTypeInformation

Write-Output "`nINFO: Report saved to: $reportPath"
