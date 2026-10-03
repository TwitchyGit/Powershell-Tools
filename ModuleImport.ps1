[CmdletBinding()]
param()

try {
    # Modules group commands. Import-Module loads commands into session command table.
    Import-Module -Name Microsoft.PowerShell.Utility -ErrorAction Stop

    Get-Command -Module Microsoft.PowerShell.Utility |
        Select-Object -First 3 -Property Name, CommandType

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
