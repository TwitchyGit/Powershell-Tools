#requires -Version 7.0
[CmdletBinding()]
param()

try {
    # requires stops script before execution when host does not meet requirement.
    [pscustomobject]@{
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        MeetsRequirement = $PSVersionTable.PSVersion -ge [version]'7.0'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
