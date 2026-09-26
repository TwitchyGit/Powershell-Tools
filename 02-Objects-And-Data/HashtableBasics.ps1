<#
.SYNOPSIS
Shows hashtable settings lookup.

.DESCRIPTION
The script reports required key validation against local sample settings.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Hashtable lookup is by key. This is faster and clearer than searching object arrays.
    $Settings = @{
        Name = 'Training'
        Enabled = $true
        MaxItems = 5
    }
    $RequiredKeys = @('Name', 'Enabled', 'MaxItems')
    $MissingKeys = $RequiredKeys | Where-Object { -not $Settings.ContainsKey($_) }

    [pscustomobject]@{
        Stage = 'HashtableLookup'
        Name = $Settings['Name']
        Enabled = $Settings.Enabled
        Keys = ($Settings.Keys -join ', ')
        MissingKeys = $MissingKeys
        Passed = $MissingKeys.Count -eq 0
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
