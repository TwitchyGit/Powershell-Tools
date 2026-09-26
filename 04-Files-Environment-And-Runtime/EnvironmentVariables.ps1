<#
.SYNOPSIS
Shows environment variable access.

.DESCRIPTION
The script reports environment values and temp path fallback behavior.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Env: exposes process environment variables through a provider.
    $TempPath = if ([string]::IsNullOrWhiteSpace($env:TEMP)) {
        [System.IO.Path]::GetTempPath()
    } else {
        $env:TEMP
    }

    [pscustomobject]@{
        Stage = 'EnvironmentSnapshot'
        TempPath = $TempPath
        TempSource = if ([string]::IsNullOrWhiteSpace($env:TEMP)) { 'GetTempPath' } else { 'TEMP' }
        Shell = $env:SHELL
        PathSeparator = [System.IO.Path]::PathSeparator
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
