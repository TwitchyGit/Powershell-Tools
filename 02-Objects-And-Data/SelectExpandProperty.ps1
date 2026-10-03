<#
.SYNOPSIS
Shows selected property wrappers and expanded values.

.DESCRIPTION
The script reports output type differences from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # ExpandProperty returns raw property value. Without it output remains an object wrapper.
    $Object = [pscustomobject]@{ Name = 'PowerShell'; Version = '7.6' }
    $Wrapped = $Object | Select-Object -Property Name
    $Expanded = $Object | Select-Object -ExpandProperty Name

    [pscustomobject]@{
        Stage = 'SelectVsExpand'
        WrappedType = $Wrapped.GetType().Name
        ExpandedType = $Expanded.GetType().Name
        WrappedProperties = $Wrapped.PSObject.Properties.Name
        Expanded = $Expanded
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
