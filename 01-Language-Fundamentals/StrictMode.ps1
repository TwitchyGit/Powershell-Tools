<#
.SYNOPSIS
Shows strict mode use.

.DESCRIPTION
The script reports strict mode state and safe property existence checking.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # StrictMode catches uninitialized variables and other loose behaviors early.
    Set-StrictMode -Version Latest
    $Name = 'PowerShell'

    [pscustomobject]@{
        Stage = 'StrictMode'
        Name = $Name
        StrictMode = 'Latest'
        PropertyExists = $null -ne ([pscustomobject]@{ Name = $Name }).PSObject.Properties['Name']
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
