<#
.SYNOPSIS
Shows module import inspection.

.DESCRIPTION
The script imports a built-in module and reports command metadata.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Modules group commands. Import-Module loads commands into session command table.
    Import-Module -Name Microsoft.PowerShell.Utility -ErrorAction Stop

    $Commands = Get-Command -Module Microsoft.PowerShell.Utility |
        Select-Object -First 3 -Property Name, CommandType

    [pscustomobject]@{
        Stage = 'ImportModule'
        ModuleName = 'Microsoft.PowerShell.Utility'
        CommandSample = $Commands
        CommandCount = $Commands.Count
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
