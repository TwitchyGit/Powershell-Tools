[CmdletBinding()]
param()

try {
    # Format-* creates display instructions. Use Select-Object when later code needs data.
    $Object = [pscustomobject]@{ Name = 'Sample'; Count = 7 }
    $Selected = $Object | Select-Object -Property Name
    $Formatted = $Object | Format-Table -Property Name

    [pscustomobject]@{
        SelectedType = $Selected.GetType().Name
        FormattedType = $Formatted[0].GetType().Name
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
