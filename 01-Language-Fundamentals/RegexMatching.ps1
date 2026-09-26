<#
.SYNOPSIS
Shows regular expression matching.

.DESCRIPTION
The script reports match state and a named capture group.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # -match sets $Matches for current scope when pattern succeeds.
    $Text = 'PowerShell 7.6'
    $Found = $Text -match 'PowerShell (?<Version>\d+\.\d+)'

    [pscustomobject]@{
        Stage = 'RegexMatching'
        Found = $Found
        Version = $Matches.Version
        Pattern = 'PowerShell (?<Version>\d+\.\d+)'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
