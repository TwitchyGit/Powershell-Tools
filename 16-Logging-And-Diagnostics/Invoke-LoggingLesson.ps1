<#
.SYNOPSIS
    Demonstrates structured logging and redaction with local sample events.
.DESCRIPTION
    Converts fixture events into JSONL-shaped objects without writing a log file.
#>
[CmdletBinding()]
param(
    [string] $FixturePath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

<#
.SYNOPSIS
    Converts one event into a redacted diagnostic record.
#>
function ConvertTo-TrainingLogRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Event,

        [Parameter(Mandatory = $true)]
        [string] $RunId
    )

    [pscustomobject]@{
        Timestamp = '2026-10-04T00:00:00Z'
        RunId = $RunId
        Level = $Event.level
        Message = $Event.message
        Secret = '[redacted]'
    }
}

try {
    $Fixture = Get-Content -Path $FixturePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    foreach ($Event in $Fixture.events) {
        ConvertTo-TrainingLogRecord -Event $Event -RunId $Fixture.runId
    }

    exit 0
} catch {
    Write-Error -Message "Logging lesson failed: $($_.Exception.Message)"
    exit 1
}
