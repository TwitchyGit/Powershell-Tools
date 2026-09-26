#requires -Version 7.0
<#
.SYNOPSIS
Shows script version requirements.

.DESCRIPTION
The script reports the current PowerShell version against its required version.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # requires stops script before execution when host does not meet requirement.
    [pscustomobject]@{
        Stage = 'RequiresVersion'
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        MeetsRequirement = $PSVersionTable.PSVersion -ge [version]'7.0'
        RequiredVersion = '7.0'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
