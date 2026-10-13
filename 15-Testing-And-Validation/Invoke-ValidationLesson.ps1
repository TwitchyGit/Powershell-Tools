<#
.SYNOPSIS
    Demonstrates fixture-backed validation and assertions without external test modules.
.DESCRIPTION
    Loads local test cases and reports whether each expected result matches the validator result.
#>
[CmdletBinding()]
param(
    [string] $FixturePath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

<#
.SYNOPSIS
    Checks whether a training package path is a safe drive-C path.
#>
function Test-TrainingPackagePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return ($Path -match '^C:/[A-Za-z0-9_ ./-]+$' -and $Path -notmatch '\.\.')
}

try {
    $Fixture = Get-Content -Path $FixturePath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    $Results = foreach ($Case in $Fixture.cases) {
        $Actual = Test-TrainingPackagePath -Path $Case.path
        [pscustomobject]@{
            Name = $Case.name
            Path = $Case.path
            ExpectedValid = [bool]$Case.expectedValid
            ActualValid = [bool]$Actual
            Passed = [bool]$Case.expectedValid -eq [bool]$Actual
        }
    }

    $Failed = @($Results | Where-Object { -not $_.Passed })
    $Results
    if ($Failed.Count -gt 0) {
        Write-Error -Message 'One or more validation lessons failed.'
        exit 1
    }

    exit 0
} catch {
    Write-Error -Message "Validation lesson failed: $($_.Exception.Message)"
    exit 1
}
