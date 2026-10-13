<#
.SYNOPSIS
    Demonstrates module packaging decisions from local sample data.
.DESCRIPTION
    Reads a synthetic module layout and returns manifest, export and folder-shape examples. No module is built,
    imported, published or installed.
.EXAMPLE
    ./Invoke-ModulePackagingLesson.ps1
.EXAMPLE
    ./Invoke-ModulePackagingLesson.ps1 -View Exports
#>
[CmdletBinding()]
param(
    [ValidateSet('Manifest', 'Exports', 'Layout')]
    [string] $View = 'Manifest',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-ModulePackagingData {
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

function New-ManifestSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Module
    )

    [pscustomobject]@{
        Name = $Module.Name
        Version = $Module.Version
        RootModule = $Module.RootModule
        CompatiblePSEditions = $Module.CompatiblePSEditions -join ', '
        RequiredModuleCount = @($Module.RequiredModules).Count
        PublicFunctionCount = @($Module.FunctionsToExport).Count
    }
}

function New-ExportSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Module
    )

    foreach ($FunctionName in $Module.FunctionsToExport) {
        [pscustomobject]@{
            FunctionName = $FunctionName
            Exported = $true
            Reason = 'Listed in FunctionsToExport'
        }
    }

    foreach ($FunctionName in $Module.PrivateFunctions) {
        [pscustomobject]@{
            FunctionName = $FunctionName
            Exported = $false
            Reason = 'Private helper stays behind the module boundary'
        }
    }
}

function New-LayoutSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Module
    )

    foreach ($File in $Module.Files) {
        $Folder = Split-Path -Path $File -Parent
        [pscustomobject]@{
            File = $File
            Area = if ([string]::IsNullOrWhiteSpace($Folder)) { 'ModuleRoot' } else { $Folder }
            IncludedInPackage = $true
        }
    }
}

try {
    $Data = Get-ModulePackagingData -Path $DataPath
    switch ($View) {
        'Manifest' {
            New-ManifestSummary -Module $Data.Module
        }
        'Exports' {
            New-ExportSummary -Module $Data.Module
        }
        'Layout' {
            New-LayoutSummary -Module $Data.Module
        }
    }

    exit 0
} catch {
    Write-Error -Message "Module packaging lesson failed. $($_.Exception.Message)"
    exit 1
}
