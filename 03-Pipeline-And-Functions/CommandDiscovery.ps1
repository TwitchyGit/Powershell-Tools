<#
.SYNOPSIS
Shows command and parameter discovery.

.DESCRIPTION
The script reports metadata for a local command lookup.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Get-Command queries available commands. Verb and noun filters keep discovery precise.
    $Command = Get-Command -Verb Get -Noun Process
    $Parameters = $Command.Parameters.Values |
        Select-Object -First 5 -Property Name, ParameterType, IsMandatory

    [pscustomobject]@{
        Stage = 'DiscoverCommand'
        CommandName = $Command.Name
        CommandType = $Command.CommandType
        Source = $Command.Source
        ParameterSample = $Parameters
    }

    $Command |
        Select-Object -Property Name, CommandType, Source

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
