<#
.SYNOPSIS
Shows switch-based routing.

.DESCRIPTION
The script reports the route selected for a local sample value.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # switch can match several clauses. continue stops current item after first chosen action.
    $Value = 'json'
    $Meaning = switch ($Value) {
        'csv' {
            'Comma separated data'
            continue
        }
        'json' {
            'Structured text data'
            continue
        }
        default {
            'Unknown format'
        }
    }

    [pscustomobject]@{
        Stage = 'SwitchStatement'
        Value = $Value
        Meaning = $Meaning
        RouteKnown = $Meaning -ne 'Unknown format'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
