<#
.SYNOPSIS
    Demonstrates error classification from local sample records.
.DESCRIPTION
    Reads synthetic failures and maps each one to a training response. No external command or service is called.
.EXAMPLE
    ./Invoke-ErrorTaxonomyLesson.ps1
.EXAMPLE
    ./Invoke-ErrorTaxonomyLesson.ps1 -View Retry
#>
[CmdletBinding()]
param(
    [ValidateSet('Classify', 'Retry')]
    [string] $View = 'Classify',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-ErrorLessonData {
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

function ConvertTo-ErrorDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Failure
    )

    [pscustomobject]@{
        Operation = $Failure.Operation
        Category = $Failure.Category
        Retryable = [bool] $Failure.Retryable
        Handling = switch ($Failure.Category) {
            'Terminating' { 'Stop the entry script and write one clear error' }
            'NonTerminating' { 'Record the item failure and continue the batch' }
            'NativeExit' { 'Check LASTEXITCODE and convert to a structured result' }
            'Transient' { 'Retry with a bounded delay' }
            default { 'Review before handling' }
        }
    }
}

function New-RetryDecision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]] $Failure
    )

    foreach ($Item in $Failure) {
        [pscustomobject]@{
            Operation = $Item.Operation
            AttemptLimit = if ($Item.Retryable) { 3 } else { 1 }
            NextAction = if ($Item.Retryable) { 'RetryThenFail' } else { 'FailFast' }
        }
    }
}

try {
    $Data = Get-ErrorLessonData -Path $DataPath
    switch ($View) {
        'Classify' {
            foreach ($Failure in $Data.Failures) {
                ConvertTo-ErrorDecision -Failure $Failure
            }
        }
        'Retry' {
            New-RetryDecision -Failure $Data.Failures
        }
    }

    exit 0
} catch {
    Write-Error -Message "Error taxonomy lesson failed. $($_.Exception.Message)"
    exit 1
}
