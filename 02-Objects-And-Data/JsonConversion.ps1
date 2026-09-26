[CmdletBinding()]
param()

try {
    # JSON conversion preserves nested structure when depth is high enough.
    $Object = [pscustomobject]@{
        Name = 'Demo'
        Meta = [pscustomobject]@{ Enabled = $true }
    }

    $Json = $Object | ConvertTo-Json -Depth 3
    $RoundTrip = $Json | ConvertFrom-Json

    [pscustomobject]@{
        Json = $Json
        Enabled = $RoundTrip.Meta.Enabled
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
