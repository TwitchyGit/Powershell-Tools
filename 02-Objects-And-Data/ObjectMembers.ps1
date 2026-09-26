<#
.SYNOPSIS
Shows object member discovery.

.DESCRIPTION
The script reports a sample of methods available on a string object.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Get-Member shows properties and methods on objects. It teaches shape before use.
    $Methods = 'PowerShell' |
        Get-Member |
        Where-Object -Property MemberType -eq 'Method' |
        Select-Object -First 5 -Property Name, MemberType

    [pscustomobject]@{
        Stage = 'InspectMembers'
        InputType = 'String'
        MethodCountSampled = $Methods.Count
        Methods = $Methods
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
