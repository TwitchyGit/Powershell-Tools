<#
.SYNOPSIS
    Demonstrates remoting-shaped and scheduled-run plans without live execution.
.DESCRIPTION
    Builds structured plan records from fixtures and does not open a remote session or register a task.
#>
[CmdletBinding()]
param(
    [string] $FixturePath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

try {
    $Fixture = Get-Content -Path $FixturePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

    foreach ($Target in $Fixture.remoting) {
        [pscustomobject]@{
            Stage = 'RemotingPlan'
            ComputerName = $Target.computerName
            Authentication = $Target.authentication
            UseSsl = [bool]$Target.useSsl
            Action = 'Would test session creation before any real remote command.'
        }
    }

    foreach ($Run in $Fixture.scheduledRuns) {
        [pscustomobject]@{
            Stage = 'ScheduledRunPlan'
            Name = $Run.name
            Executable = $Run.executable
            Arguments = $Run.arguments
            Action = 'Would register or document a noninteractive scheduled command.'
        }
    }

    exit 0
} catch {
    Write-Error -Message "Execution plan lesson failed: $($_.Exception.Message)"
    exit 1
}
