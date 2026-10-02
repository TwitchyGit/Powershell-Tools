<#
.SYNOPSIS
Shows the Windows Credential Manager training pattern.

.DESCRIPTION
The script reports the checks required before using Windows Credential Manager from PowerShell.

.NOTES
The script does not read Windows Credential Manager entries.
#>
[CmdletBinding()]
param()

try {
    $IsWindowsHost = $PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows
    $Checks = @(
        'Confirm Windows host'
        'Choose approved module or native API wrapper'
        'Read only named target entries'
        'Redact returned secret values'
        'Remove stale entries during offboarding'
    )

    foreach ($Check in $Checks) {
        [pscustomobject]@{
            Check = $Check
            WindowsHost = [bool]$IsWindowsHost
            LiveCredentialRead = $false
            Result = if ($IsWindowsHost) { 'Ready for controlled live lab' } else { 'Documented pattern only' }
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
