<#
.SYNOPSIS
Shows splatted command parameters.

.DESCRIPTION
The script reports splat keys and command output.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Splatting names arguments once. Calls stay readable as parameter count grows.
    $SelectParams = @{
        First = 3
        Property = 'Name'
    }

    $Commands = Get-Command -Noun Process | Select-Object @SelectParams
    [pscustomobject]@{
        Stage = 'SplatCommand'
        SplatKeys = $SelectParams.Keys
        CommandCount = $Commands.Count
        Commands = $Commands
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
