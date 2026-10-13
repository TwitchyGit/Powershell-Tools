<#
.SYNOPSIS
    Demonstrates a final local course assessment from sample submissions.
.DESCRIPTION
    Reads synthetic learner submissions and scores whether each required section is present. No files are submitted,
    published or graded outside the local sample data.
.EXAMPLE
    ./Invoke-CapstoneAssessment.ps1
.EXAMPLE
    ./Invoke-CapstoneAssessment.ps1 -View Detail
#>
[CmdletBinding()]
param(
    [ValidateSet('Summary', 'Detail')]
    [string] $View = 'Summary',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-CapstoneData {
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

function Test-CapstoneSubmission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Submission,

        [Parameter(Mandatory = $true)]
        [string[]] $RequiredSection
    )

    $Missing = foreach ($Section in $RequiredSection) {
        if (-not [bool] $Submission.$Section) {
            $Section
        }
    }

    [pscustomobject]@{
        Learner = $Submission.Learner
        Passed = @($Missing).Count -eq 0
        MissingSection = if (@($Missing).Count -eq 0) { 'None' } else { $Missing -join ', ' }
    }
}

function New-CapstoneDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Submission,

        [Parameter(Mandatory = $true)]
        [string[]] $RequiredSection
    )

    foreach ($Section in $RequiredSection) {
        [pscustomobject]@{
            Learner = $Submission.Learner
            Section = $Section
            Complete = [bool] $Submission.$Section
        }
    }
}

try {
    $Data = Get-CapstoneData -Path $DataPath
    switch ($View) {
        'Summary' {
            foreach ($Submission in $Data.Assessment.Submissions) {
                Test-CapstoneSubmission -Submission $Submission -RequiredSection $Data.Assessment.RequiredSections
            }
        }
        'Detail' {
            foreach ($Submission in $Data.Assessment.Submissions) {
                New-CapstoneDetail -Submission $Submission -RequiredSection $Data.Assessment.RequiredSections
            }
        }
    }

    exit 0
} catch {
    Write-Error -Message "Capstone assessment failed. $($_.Exception.Message)"
    exit 1
}
