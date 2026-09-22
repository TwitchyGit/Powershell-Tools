[CmdletBinding()]
param()

try {
    # ExpandProperty returns raw property value. Without it output remains an object wrapper.
    $Object = [pscustomobject]@{ Name = 'PowerShell'; Version = '7.6' }
    $Wrapped = $Object | Select-Object -Property Name
    $Expanded = $Object | Select-Object -ExpandProperty Name

    [pscustomobject]@{
        WrappedType = $Wrapped.GetType().Name
        ExpandedType = $Expanded.GetType().Name
        Expanded = $Expanded
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
