<#
.SYNOPSIS
Report-only comparison between a golden source folder and one or more compare folders

.DESCRIPTION
1. For each file in $GoldenSource:
   - Look in each folder in $CompareFolders for a file with the same name
   - If any compare folder has a newer copy (LastWriteTime later than GoldenSource)
     report "Newer in <folder>"
   - If no compare folder has a newer copy report "No change"

2. Then build a list of files that exist only in compare folders
   - For each such file name show only the newest copy and which folder it is in

.\CompareDirectories.ps1 -GoldenSource 'C:\GoldenSource' `
    -CompareFolders 'C:\FolderA','C:\FolderB','D:\AnotherFolder'
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$GoldenSource,

    [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
    [string[]]$CompareFolders
)

# =======================
# VALIDATION
# =======================

if (-not (Test-Path -Path $GoldenSource -PathType Container)) {
    Write-Error "GoldenSource folder not found: $GoldenSource"
    exit 1
}

if (-not $CompareFolders -or $CompareFolders.Count -eq 0) {
    Write-Error "No compare folders defined in `\$CompareFolders"
    exit 1
}

$validCompareFolders = @()

foreach ($folder in $CompareFolders) {
    if (Test-Path -Path $folder -PathType Container) {
        $validCompareFolders += $folder
    }
    else {
        Write-Warning "Compare folder not found and will be skipped: $folder"
    }
}

if ($validCompareFolders.Count -eq 0) {
    Write-Error "None of the compare folders exist. Nothing to do"
    exit 1
}

# =======================
# COLLECT FILE LISTS
# =======================

# Golden source files (non recursive, change if you want recursion)
$goldenFiles = Get-ChildItem -Path $GoldenSource -File -ErrorAction Stop

# All files in compare folders
$allCompareFiles = @()

foreach ($folder in $validCompareFolders) {
    $folderFiles = Get-ChildItem -Path $folder -File -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            Name          = $_.Name
            FullName      = $_.FullName
            Folder        = $folder
            Length        = $_.Length
            LastWriteTime = $_.LastWriteTime
        }
    }

    $allCompareFiles += $folderFiles
}

# =======================
# PART 1
# Compare each golden file
# =======================

$comparisonReport = foreach ($g in $goldenFiles) {
    $matches = $allCompareFiles | Where-Object { $_.Name -eq $g.Name }

    $goldenTime   = $g.LastWriteTime
    $goldenLength = $g.Length

    # Any compare file strictly newer than golden
    $newerMatches = $matches | Where-Object { $_.LastWriteTime -gt $goldenTime }

    if ($newerMatches) {
        # Pick the newest of the newer ones
        $newest = $newerMatches | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $status = "Newer in $($newest.Folder)"
        $newestFolder = $newest.Folder
        $newestTime   = $newest.LastWriteTime
    }
    else {
        # No compare copy is newer than golden
        $status = 'No change'
        $newestFolder = $GoldenSource
        $newestTime   = $goldenTime
    }

    [PSCustomObject]@{
        FileName         = $g.Name
        GoldenSourcePath = $g.FullName
        GoldenSourceTime = $goldenTime
        NewestLocation   = $newestFolder
        NewestTime       = $newestTime
        Status           = $status
    }
}

Write-Output ''
Write-Output '=== Golden source comparison (Newer in <folder> or No change) ==='
$comparisonReport |
    Sort-Object FileName |
    Format-Table FileName, Status, NewestLocation, NewestTime, GoldenSourceTime -AutoSize

# =======================
# PART 2
# Files only in compare folders
# =======================

$goldenNames = $goldenFiles.Name

$compareOnly = $allCompareFiles |
    Where-Object { $goldenNames -notcontains $_.Name }

$extraFilesReport = $compareOnly |
    Group-Object Name |
    ForEach-Object {
        $newest = $_.Group | Sort-Object LastWriteTime -Descending | Select-Object -First 1

        [PSCustomObject]@{
            FileName   = $_.Name
            Folder     = $newest.Folder
            FullName   = $newest.FullName
            NewestTime = $newest.LastWriteTime
        }
    }

Write-Output ''
Write-Output '=== Files not found in GoldenSource (newest copy only) ==='
$extraFilesReport |
    Sort-Object FileName |
    Format-Table FileName, Folder, NewestTime, FullName -AutoSize
