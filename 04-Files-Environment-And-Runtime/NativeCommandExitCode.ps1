<#
.SYNOPSIS
Shows native exit-code capture.

.DESCRIPTION
The script reports native process failure separately from cmdlet failure.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Native tools set LASTEXITCODE. PowerShell cmdlets use error records instead.
    if ($IsWindows) {
        cmd.exe /c exit 7
    } else {
        /bin/sh -c 'exit 7'
    }

    $NativeExitCode = $LASTEXITCODE
    $CmdletSucceeded = $true
    try {
        Get-Item -Path '__missing_file__' -ErrorAction Stop | Out-Null
    } catch {
        $CmdletSucceeded = $false
    }

    [pscustomobject]@{
        Stage = 'CompareNativeAndCmdletFailure'
        NativeExitCode = $NativeExitCode
        CmdletSucceeded = $CmdletSucceeded
        NativeFailureCapturedBeforeCmdlet = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
