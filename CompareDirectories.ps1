<#
.SYNOPSIS
Compares a golden source folder with one or more compare folders

.DESCRIPTION
1. For every file in $GoldenSource, finds the newest copy across all folders
   and reports if a newer copy exists in any compare folder

2. Builds a list of files that exist only in compare folders
   For those, shows only the newest copy and which compare folder it is in

No files are changed

.\CompareDirectories.ps1 -GoldenSource 'C:\GoldenSource' `
    -CompareFolders 'C:\FolderA','C:\FolderB','D:\AnotherFolder'
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$GoldenSource,

    [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
    [string[]]$CompareFolders
)

# Validate golden source
if (-not (Test-Path -Path $GoldenSource -PathType Container)) {
    Write-Error "GoldenSource folder not found: $GoldenSource"
    exit 1
}

# Validate compare folders and collect files
$allCompareFiles = @()

foreach ($folder in $CompareFolders) {
    if (-not (Test-Path -Path $folder -PathType Container)) {
        Write-Warning "Compare folder not found and will be skipped: $folder"
        continue
    }

    $folderFiles = Get-ChildItem -Path $folder -File -ErrorAction Stop | ForEach-Object {
        [PSCustomObject]@{
            Name         = $_.Name
            FullName     = $_.FullName
            Folder       = $folder
            LastWriteTime = $_.LastWriteTime
        }
    }

    $allCompareFiles += $folderFiles
}

# Get golden source files
$goldenFiles = Get-ChildItem -Path $GoldenSource -File -ErrorAction Stop

# Report 1
# For each golden file work out the newest copy across golden and compare folders
$goldenReport = foreach ($g in $goldenFiles) {
    $matches = $allCompareFiles | Where-Object { $_.Name -eq $g.Name }

    # Build candidate list including the golden copy
    $candidates = @(
        [PSCustomObject]@{
            Source       = 'GoldenSource'
            Folder       = $GoldenSource
            Name         = $g.Name
            FullName     = $g.FullName
            LastWriteTime = $g.LastWriteTime
        }
    )

    if ($matches) {
        $candidates += $matches | Select-Object @{
            Name       = 'Source'
            Expression = { 'Compare' }
        }, Folder, Name, FullName, LastWriteTime
    }

    $newest = $candidates | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $status = if ($newest.Source -eq 'GoldenSource') {
        'Latest in GoldenSource'
    }
    else {
        "Newer in $($newest.Folder)"
    }

    [PSCustomObject]@{
        FileName         = $g.Name
        GoldenSourcePath = $g.FullName
        GoldenSourceTime = $g.LastWriteTime
        NewestLocation   = $newest.Folder
        NewestTime       = $newest.LastWriteTime
        Status           = $status
    }
}

Write-Output "=== Files where a compare folder has a newer copy than GoldenSource ==="
$goldenReport |
    Where-Object { $_.Status -like 'Newer in *' } |
    Sort-Object FileName |
    Format-Table FileName, Status, NewestLocation, NewestTime, GoldenSourceTime -AutoSize

# Report 2
# Files that exist only in compare folders (not in GoldenSource)
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

Write-Output "=== Files not found in GoldenSource (showing newest copy only) ==="
$extraFilesReport |
    Sort-Object FileName |
    Format-Table FileName, Folder, NewestTime, FullName -AutoSize
