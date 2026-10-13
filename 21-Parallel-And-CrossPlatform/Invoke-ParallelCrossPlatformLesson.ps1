<#
.SYNOPSIS
    Demonstrates parallel execution planning and cross-platform checks from sample data.
.DESCRIPTION
    Reads synthetic task records and returns throttle, ordering and platform decisions. The lesson does not start jobs,
    runspaces or remote commands.
.EXAMPLE
    ./Invoke-ParallelCrossPlatformLesson.ps1
.EXAMPLE
    ./Invoke-ParallelCrossPlatformLesson.ps1 -View Platform
#>
[CmdletBinding()]
param(
    [ValidateSet('Plan', 'Platform')]
    [string] $View = 'Plan',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-ParallelLessonData {
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

function New-ParallelPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]] $Task,

        [Parameter(Mandatory = $true)]
        [int] $ThrottleLimit
    )

    $Index = 0
    foreach ($Item in $Task) {
        $Index++
        $OrderingRule = if ($Item.UsesSharedState) {
            'Run serial to avoid shared-state races'
        } else {
            'May run within throttle limit'
        }

        [pscustomobject]@{
            Name = $Item.Name
            Batch = [math]::Ceiling($Index / $ThrottleLimit)
            CanRunInParallel = -not [bool] $Item.UsesSharedState
            OrderingRule = $OrderingRule
        }
    }
}

function New-PlatformPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]] $Task,

        [Parameter(Mandatory = $true)]
        [string[]] $Platform
    )

    foreach ($Item in $Task) {
        foreach ($Name in $Platform) {
            $Boundary = if ($Item.WindowsOnly) {
                'Windows-only API or provider'
            } else {
                'PowerShell 7 portable shape'
            }

            [pscustomobject]@{
                Task = $Item.Name
                Platform = $Name
                Supported = -not $Item.WindowsOnly -or $Name -eq 'Windows'
                Boundary = $Boundary
            }
        }
    }
}

try {
    $Data = Get-ParallelLessonData -Path $DataPath
    switch ($View) {
        'Plan' {
            New-ParallelPlan -Task $Data.Tasks -ThrottleLimit $Data.ThrottleLimit
        }
        'Platform' {
            New-PlatformPlan -Task $Data.Tasks -Platform $Data.Platforms
        }
    }

    exit 0
} catch {
    Write-Error -Message "Parallel and cross-platform lesson failed. $($_.Exception.Message)"
    exit 1
}
