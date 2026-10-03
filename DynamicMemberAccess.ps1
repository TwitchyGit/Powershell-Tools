[CmdletBinding()]
param()

try {
    # Property names can come from variables. This helps generic object processing.
    $PropertyName = 'Length'
    $Text = 'PowerShell'

    [pscustomobject]@{
        Property = $PropertyName
        Value = $Text.$PropertyName
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
