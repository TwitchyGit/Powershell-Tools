<#
.SYNOPSIS
Shows common type accelerators.

.DESCRIPTION
The script reports full type names for accelerator-created values.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Type accelerators are short names for common .NET types.
    $Version = [version]'7.6.0'
    $Guid = [guid]::NewGuid()

    [pscustomobject]@{
        Stage = 'TypeAccelerators'
        VersionType = $Version.GetType().FullName
        GuidType = $Guid.GetType().FullName
        GuidIsEmpty = $Guid -eq [guid]::Empty
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
