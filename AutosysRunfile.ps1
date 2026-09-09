$exitValue = 0
$pwshPath = 'C:\Program Files\PowerShell\7\pwsh.exe'

# PowerShell7 update: AutoSys receives only the approved success or failure exit code.
trap {
    Write-Output "ERROR: Unhandled AutoSys wrapper failure: $($_.Exception.Message)"
    exit 1
}

# Run the processes
$RunScript = "C:\Cyb-User-Onboarding\Scan-HumanUsers.ps1"
$exitCode = 1
try {
    $LASTEXITCODE = $null
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -NonInteractive `
        -File $RunScript `
        -SourceDir "$ConfDirLogs" `
        -ArchiveDir "D:\Logs\Reports_Archive"
    if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE }
} catch {
    Write-Output "ERROR: Unable to launch PowerShell 7 for '$RunScript': $($_.Exception.Message)"
}
if ($exitCode -ne 0) {
    Write-Output "ERROR: '$RunScript' returned exit code $exitCode"
}
if ($exitCode -ne 0) { $exitValue = 1 }

$RunScript = "C:\Cyb-User-Onboarding\Scan-AllObjectsInSafes.ps1"
$exitCode = 1
try {
    $LASTEXITCODE = $null
    & $pwshPath -NoProfile -NonInteractive -File $RunScript -ReportSafes
    if ($null -ne $LASTEXITCODE) { $exitCode = [int]$LASTEXITCODE }
} catch {
    Write-Output "ERROR: Unable to launch PowerShell 7 for '$RunScript': $($_.Exception.Message)"
}
if ($exitCode -ne 0) {
    Write-Output "ERROR: '$RunScript' returned exit code $exitCode"
}
if ($exitCode -ne 0) { $exitValue = 1 }

if ($exitValue -ne 0) {
    Write-Output "ERROR: One or more reports failed to generate."
    exit 1
}

Write-Output "INFO: All requested reports completed successfully."
exit 0
