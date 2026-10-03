<#
.SYNOPSIS
Shows JSON round-trip conversion.

.DESCRIPTION
The script reports nested JSON shape after conversion from and to objects.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # JSON conversion preserves nested structure when depth is high enough.
    $Object = [pscustomobject]@{
        Name = 'Demo'
        Meta = [pscustomobject]@{
            Enabled = $true
            Tags = @('Training', 'Json')
        }
    }

    $Json = $Object | ConvertTo-Json -Depth 3
    $RoundTrip = $Json | ConvertFrom-Json

    [pscustomobject]@{
        Stage = 'JsonRoundTrip'
        Json = $Json
        Enabled = $RoundTrip.Meta.Enabled
        TagCount = $RoundTrip.Meta.Tags.Count
        TypeAfterImport = $RoundTrip.GetType().Name
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
