<#
.SYNOPSIS
    Shows the runnable sample data for this section with several local examples.
.DESCRIPTION
    Loads fixtures/sample-data.json and returns structured objects that can be inspected, filtered or exported.
    The examples use only synthetic local data and do not call live services.
#>
[CmdletBinding()]
param(
    [ValidateSet('Overview', 'FirstCollection', 'AllCollections')]
    [string] $View = 'Overview',
    [string] $FixturePath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

<#
.SYNOPSIS
    Loads this section's sample data so the examples run from a predictable local fixture.
#>
function Import-SectionSampleData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        Write-Error -Message "Sample data file not found: $Path" -ErrorAction Stop
    }

    Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

<#
.SYNOPSIS
    Lists the named collections in the fixture so learners can see what data the section uses.
#>
function Get-SectionSampleCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Data
    )

    foreach ($Property in $Data.PSObject.Properties) {
        if ($Property.Name -eq 'purpose') {
            continue
        }

        $Value = $Property.Value
        $IsCollection = $Value -is [System.Array] -or $Value -is [pscustomobject]
        if ($IsCollection) {
            $Count = if ($Value -is [System.Array]) { $Value.Count } else { 1 }
            [pscustomobject]@{
                Collection = $Property.Name
                ItemCount = $Count
                Sample = $Value
            }
        }
    }
}

<#
.SYNOPSIS
    Returns one of the section's sample views so the same data can be inspected in several ways.
#>
function Invoke-SectionSampleExample {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Overview', 'FirstCollection', 'AllCollections')]
        [string] $View,
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Data
    )

    $Collections = @(Get-SectionSampleCollection -Data $Data)

    if ($View -eq 'Overview') {
        [pscustomobject]@{
            Section = Split-Path -Path $PSScriptRoot -Leaf
            Purpose = $Data.purpose
            CollectionCount = $Collections.Count
            Collections = $Collections.Collection -join ', '
        }
        return
    }

    if ($View -eq 'FirstCollection') {
        $First = $Collections | Select-Object -First 1
        [pscustomobject]@{
            Section = Split-Path -Path $PSScriptRoot -Leaf
            Collection = $First.Collection
            ItemCount = $First.ItemCount
            Sample = $First.Sample
        }
        return
    }

    foreach ($Collection in $Collections) {
        [pscustomobject]@{
            Section = Split-Path -Path $PSScriptRoot -Leaf
            Collection = $Collection.Collection
            ItemCount = $Collection.ItemCount
            Sample = $Collection.Sample
        }
    }
}

try {
    $SampleData = Import-SectionSampleData -Path $FixturePath
    Invoke-SectionSampleExample -View $View -Data $SampleData
    exit 0
} catch {
    Write-Error -Message "Sample data example failed: $($_.Exception.Message)"
    exit 1
}
