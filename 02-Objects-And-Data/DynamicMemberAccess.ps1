<#
.SYNOPSIS
Shows member access by property name.

.DESCRIPTION
The script reports a dynamic property lookup against local sample text.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Property names can come from variables. This helps generic object processing.
    $PropertyName = 'Length'
    $Text = 'PowerShell'
    $PropertyExists = $Text.PSObject.Properties[$PropertyName] -or
        $Text.GetType().GetProperty($PropertyName)

    [pscustomobject]@{
        Stage = 'DynamicMemberAccess'
        Property = $PropertyName
        PropertyExists = [bool]$PropertyExists
        Value = $Text.$PropertyName
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
