<#
.SYNOPSIS
    Demonstrates argument-completer choices from local sample data.
.DESCRIPTION
    Reads synthetic command metadata and returns the completions a learner would expect. No completer is registered.
.EXAMPLE
    ./Invoke-ArgumentCompleterLesson.ps1
.EXAMPLE
    ./Invoke-ArgumentCompleterLesson.ps1 -View RegistrationPlan
#>
[CmdletBinding()]
param(
    [ValidateSet('Complete', 'RegistrationPlan')]
    [string] $View = 'Complete',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-CompleterLessonData {
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

function Get-TrainingCompletion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Command,

        [Parameter(Mandatory = $true)]
        [string] $InputText
    )

    foreach ($Choice in $Command.Choices | Where-Object { $_ -like "$InputText*" }) {
        [pscustomobject]@{
            CommandName = $Command.Name
            ParameterName = $Command.Parameter
            CompletionText = $Choice
            ListItemText = $Choice
        }
    }
}

function New-CompleterRegistrationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]] $Command
    )

    foreach ($Item in $Command) {
        [pscustomobject]@{
            CommandName = $Item.Name
            ParameterName = $Item.Parameter
            CompletionSource = 'Local fixture choices'
            ValidationPattern = ($Item.Choices -join '|')
        }
    }
}

try {
    $Data = Get-CompleterLessonData -Path $DataPath
    switch ($View) {
        'Complete' {
            foreach ($Command in $Data.Commands) {
                Get-TrainingCompletion -Command $Command -InputText $Data.Input
            }
        }
        'RegistrationPlan' {
            New-CompleterRegistrationPlan -Command $Data.Commands
        }
    }

    exit 0
} catch {
    Write-Error -Message "Argument completer lesson failed. $($_.Exception.Message)"
    exit 1
}
