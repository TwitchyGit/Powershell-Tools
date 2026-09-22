[CmdletBinding()]
param()

try {
    # Type accelerators are short names for common .NET types.
    $Version = [version]'7.6.0'
    $Guid = [guid]::NewGuid()

    [pscustomobject]@{
        VersionType = $Version.GetType().FullName
        GuidType = $Guid.GetType().FullName
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
