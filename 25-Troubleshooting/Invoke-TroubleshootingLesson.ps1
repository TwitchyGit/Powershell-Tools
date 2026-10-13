<#
.SYNOPSIS
    Demonstrates troubleshooting bundles from local sample incidents.
.DESCRIPTION
    Reads synthetic incidents and returns the evidence needed for reproducible diagnosis. No trace, event log or
    platform command is run.
.EXAMPLE
    ./Invoke-TroubleshootingLesson.ps1
.EXAMPLE
    ./Invoke-TroubleshootingLesson.ps1 -View Bundle
#>
[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Bundle')]
    [string] $View = 'Plan',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-TroubleshootingData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        Write-Error -Message "Sample data file was not found: $Path" -ErrorAction Stop
    }

    Get-Content -Path $Path -Raw | ConvertFrom-Json
}

function New-DiagnosticPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Incident
    )

    [pscustomobject]@{
        Id = $Incident.Id
        Symptom = $Incident.Symptom
        LikelyLayer = $Incident.LikelyLayer
        FirstQuestion = switch ($Incident.LikelyLayer) {
            'Data' { 'Can the same input reproduce the result?' }
            'Runtime' { 'What exit code and platform were recorded?' }
            default { 'Which boundary changed first?' }
        }
    }
}

function New-DiagnosticBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Incident
    )

    [pscustomobject]@{
        Id = $Incident.Id
        BundleName = "$($Incident.Id)-diagnostic-bundle"
        Evidence = $Incident.Evidence -join ', '
        SafeToShare = $true
    }
}

try {
    $Data = Get-TroubleshootingData -Path $DataPath
    switch ($View) {
        'Plan' {
            foreach ($Incident in $Data.Incidents) {
                New-DiagnosticPlan -Incident $Incident
            }
        }
        'Bundle' {
            foreach ($Incident in $Data.Incidents) {
                New-DiagnosticBundle -Incident $Incident
            }
        }
    }

    exit 0
} catch {
    Write-Error -Message "Troubleshooting lesson failed. $($_.Exception.Message)"
    exit 1
}
