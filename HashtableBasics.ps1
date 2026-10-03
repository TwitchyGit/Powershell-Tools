[CmdletBinding()]
param()

try {
    # Hashtable lookup is by key. This is faster and clearer than searching object arrays.
    $Settings = @{
        Name = 'Training'
        Enabled = $true
        MaxItems = 5
    }

    [pscustomobject]@{
        Name = $Settings['Name']
        Enabled = $Settings.Enabled
        Keys = ($Settings.Keys -join ', ')
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
