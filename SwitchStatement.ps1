[CmdletBinding()]
param()

try {
    # switch can match several clauses. continue stops current item after first chosen action.
    $Value = 'json'

    switch ($Value) {
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

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
