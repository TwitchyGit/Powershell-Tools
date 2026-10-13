<#
.SYNOPSIS
    Demonstrates Windows PowerShell 5.1 to PowerShell 7.6+ upgrade decisions from local examples.
.DESCRIPTION
    Reads synthetic side-by-side migration examples and returns structured upgrade decisions. The lesson does not run
    Active Directory, WinRM, Git, certificate-store or live web checks.
.EXAMPLE
    ./Invoke-UpgradeReadinessLesson.ps1
.EXAMPLE
    ./Invoke-UpgradeReadinessLesson.ps1 -View Examples
.EXAMPLE
    ./Invoke-UpgradeReadinessLesson.ps1 -View Checklist
#>
[CmdletBinding()]
param(
    [ValidateSet('Summary', 'Examples', 'Checklist')]
    [string] $View = 'Summary',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-UpgradeLessonData {
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

function New-UpgradeSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]] $Example
    )

    $Example |
        Group-Object -Property Decision |
        Sort-Object -Property Name |
        ForEach-Object {
            [pscustomobject]@{
                Decision = $_.Name
                ExampleCount = $_.Count
                Patterns = ($_.Group.Pattern -join ', ')
            }
        }
}

function New-UpgradeExample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]] $Example
    )

    foreach ($Item in $Example) {
        [pscustomobject]@{
            Pattern = $Item.Pattern
            WindowsPowerShell51 = $Item.WindowsPowerShell51
            PowerShell76 = $Item.PowerShell76
            Decision = $Item.Decision
            Reason = $Item.Reason
        }
    }
}

function New-UpgradeChecklistItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]] $Checklist
    )

    $Index = 0
    foreach ($Item in $Checklist) {
        $Index++
        [pscustomobject]@{
            Step = $Index
            Check = $Item
        }
    }
}

try {
    $Data = Get-UpgradeLessonData -Path $DataPath
    switch ($View) {
        'Summary' {
            New-UpgradeSummary -Example $Data.examples
        }
        'Examples' {
            New-UpgradeExample -Example $Data.examples
        }
        'Checklist' {
            New-UpgradeChecklistItem -Checklist $Data.checklist
        }
    }

    exit 0
} catch {
    Write-Error -Message "Upgrade readiness lesson failed. $($_.Exception.Message)"
    exit 1
}
