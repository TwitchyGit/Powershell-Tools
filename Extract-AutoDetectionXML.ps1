<#
.SYNOPSIS
    Extracts ADProcess configurations from a CyberArk CPM AutoDetection XML file.

.DESCRIPTION
    Parses the <ADProcesses> block of the supplied XML file and outputs:
      The top-level ADReloadInterval and ADPerformAutomaticDetectionTask settings.
      A table with one row per <ADProcess>, listing the key configuration values.

.PARAMETER Template
    Full path to the XML file to parse.

.PARAMETER Export
    Optional. If supplied, also exports the table to the given CSV path.

.EXAMPLE
    .\Extract-AutoDetectionXML.ps1 -Template 'C:\Temp\ADConfig.xml'

.EXAMPLE
    .\Extract-AutoDetectionXML.ps1 -Template 'C:\Temp\ADConfig.xml' -Export 'C:\Temp\ADProcesses.csv'
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })][string]$Template,
    [Parameter(Mandatory = $false)][string]$Export
)


# Helper Functions
function Get-Attribute {
    <#
        Safely returns a named attribute from an XmlElement, or $null if the
        element / attribute is missing. Avoids null-reference errors on PS 5.1.
    #>
    [CmdletBinding()]
    param(
        [System.Xml.XmlElement]$Element,
        [string]$AttributeName
    )

    if ($null -eq $Element) { return $null }
    if (-not $Element.HasAttribute($AttributeName)) { return $null }
    return $Element.GetAttribute($AttributeName)
}

function Get-XMLElement {
    <#
        Returns the first direct child element with the given local name, or
        $null if not found.
    #>
    [CmdletBinding()]
    param(
        [System.Xml.XmlElement]$Parent,
        [string]$Name
    )

    if ($null -eq $Parent) { return $null }
    foreach ($child in $Parent.ChildNodes) {
        if ($child.NodeType -eq [System.Xml.XmlNodeType]::Element -and $child.LocalName -eq $Name) {
            return $child
        }
    }
    return $null
}


#  Load XML
try {
    [xml]$xml = Get-Content -LiteralPath $Template -Raw -ErrorAction Stop
} catch {
    Write-Error "Failed to load XML from '$Template': $_"
    return
}

$adConfig = $xml.ADConfiguration
if ($null -eq $adConfig) {
    Write-Error "No <ADConfiguration> root element found in '$Template'."
    return
}

# Top-level settings

$reloadInterval     = Get-Attribute -Element $adConfig -AttributeName 'ADReloadInterval'
$autoDetectionTask  = Get-Attribute -Element $adConfig -AttributeName 'ADPerformAutomaticDetectionTask'

Write-Output ''
Write-Output '=== ADConfiguration (top-level settings) ==='
[pscustomobject]@{
    ADReloadInterval                 = $reloadInterval
    ADPerformAutomaticDetectionTask  = $autoDetectionTask
} | Format-List

# Per-process extraction

$processesContainer = Get-XMLElement -Parent $adConfig -Name 'ADProcesses'
if ($null -eq $processesContainer) {
    Write-Error "No <ADProcesses> block found under <ADConfiguration>."
    return
}

$results = New-Object System.Collections.Generic.List[object]

foreach ($proc in $processesContainer.ChildNodes) {
    if ($proc.NodeType -ne [System.Xml.XmlNodeType]::Element) { continue }
    if ($proc.LocalName -ne 'ADProcess') { continue }

    # Exclusion filter - skip any defaults
    $procName = Get-Attribute -Element $proc -AttributeName 'ADProcessName'
    if ($procName -like 'Policy Based*' -or $procName -like 'Local Administrators*') {
        Write-Output "INFO: Skipping excluded ADProcess '$procName'"
        continue
    }

    # Drill into the nested elements once, defensively.
    $machineDetection   = Get-XMLElement -Parent $proc              -Name 'ADMachineDetection'
    $ldapDetection      = Get-XMLElement -Parent $machineDetection  -Name 'ADLDAPDetection'
    $ldapConnDetails    = Get-XMLElement -Parent $ldapDetection     -Name 'ADLDAPConnectionDetails'
    $machineSets        = Get-XMLElement -Parent $ldapDetection     -Name 'ADMachineSets'
    $detectionInterval  = Get-XMLElement -Parent $ldapDetection     -Name 'ADMachineDetectionInterval'

    $accountMgmt        = Get-XMLElement -Parent $proc              -Name 'ADAccountManagement'
    $newAcctSettings    = Get-XMLElement -Parent $accountMgmt       -Name 'ADNewAccountSettings'
    $localAcctTemplate  = Get-XMLElement -Parent $newAcctSettings   -Name 'ADLocalAccountTemplate'

    $machineScan        = Get-XMLElement -Parent $proc              -Name 'ADMachineScan'
    $machineScanInt     = Get-XMLElement -Parent $machineScan       -Name 'ADMachineScanInterval'

    # Collect every ADMachineSet under ADMachineSets - there may be one or more.
    # If none exist, use a single $null placeholder so the process still emits a row.
    $machineSetElements = @()
    if ($null -ne $machineSets) {
        $machineSetElements = @($machineSets.ChildNodes | Where-Object {
            $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and $_.LocalName -eq 'ADMachineSet'
        })
    }
    if ($machineSetElements.Count -eq 0) { $machineSetElements = @($null) }

    # Build one candidate row per ADMachineSet.
    $machineSetRows = New-Object System.Collections.Generic.List[object]
    foreach ($machineSet in $machineSetElements) {
        $machineSetRows.Add([pscustomobject][ordered]@{
            ADProcessName                 = (Get-Attribute -Element $proc -AttributeName 'ADProcessName')
            ADProcessActive               = (Get-Attribute -Element $proc -AttributeName 'ADProcessActive')
            ADProcessID                   = (Get-Attribute -Element $proc -AttributeName 'ADProcessID')
            ADLDAPDebug                   = (Get-Attribute -Element $ldapDetection -AttributeName 'ADLDAPDebug')
            ADLDAPConnectionAccountSafe   = (Get-Attribute -Element $ldapConnDetails `
                -AttributeName 'ADLDAPConnectionAccountSafe')
            ADLDAPConnectionAccountObject = (Get-Attribute -Element $ldapConnDetails `
                -AttributeName 'ADLDAPConnectionAccountObject')
            ADMachineWorkspaceSafe        = (Get-Attribute -Element $machineSet -AttributeName 'ADMachineWorkspaceSafe')
            ADBaseContext                 = (Get-Attribute -Element $machineSet -AttributeName 'ADBaseContext')
            ADQueryFilter                 = (Get-Attribute -Element $machineSet -AttributeName 'ADQueryFilter')
            ADIsQueryFilterRecursive      = (Get-Attribute -Element $machineSet `
                -AttributeName 'ADIsQueryFilterRecursive')
            ADMachineDetectionInterval    = (Get-Attribute -Element $detectionInterval `
                -AttributeName 'ADMachineDetectionInterval')
            ADLocalAccountTemplateSafe    = (Get-Attribute -Element $localAcctTemplate `
                -AttributeName 'ADLocalAccountTemplateSafe')
            ADLocalAccountTemplateObject  = (Get-Attribute -Element $localAcctTemplate `
                -AttributeName 'ADLocalAccountTemplateObject')
            ADMachineScanInterval         = (Get-Attribute -Element $machineScanInt `
                -AttributeName 'ADMachineScanInterval')
        }) | Out-Null
    }

    # Collapse rows that differ only by ADBaseContext into a single '|'-delimited
    # row. Any difference in another field forces a separate row.
    $keyProperties = $machineSetRows[0].PSObject.Properties.Name | Where-Object { $_ -ne 'ADBaseContext' }

    $grouped = $machineSetRows | Group-Object -Property {
        $r = $_
        ($keyProperties | ForEach-Object { "$_=$($r.$_)" }) -join ([char]0x1F)
    }

    foreach ($group in $grouped) {
        $merged = $group.Group[0]
        $baseContexts = @($group.Group.ADBaseContext | Where-Object { $null -ne $_ } | Select-Object -Unique)
        $merged.ADBaseContext = $baseContexts -join '|'
        $results.Add($merged) | Out-Null
    }
}

if ($results.Count -eq 0) {
    Write-Warning "No <ADProcess> entries were found inside <ADProcesses>."
    return
}

Write-Output ''
Write-Output "=== ADProcess entries ($($results.Count) found) ==="

# Table view to the console. Use Format-Table -AutoSize for readability.
$tableText = $results | Format-Table -AutoSize -Wrap | Out-String -Width 4096
Write-Information -MessageData $tableText -InformationAction Continue

# Also push the raw objects down the pipeline so the caller can capture them.
$results

# Optional CSV export
if ($PSBoundParameters.ContainsKey('Export') -and -not [string]::IsNullOrWhiteSpace($Export)) {
    try {
        # Write the document-level settings as a small preamble first...
        $preamble = @(
            "ADReloadInterval,$reloadInterval"
            "ADPerformAutomaticDetectionTask,$autoDetectionTask"
            ""   # blank line to separate the preamble from the table
        )
        Set-Content -LiteralPath $Export -Value $preamble -Encoding UTF8

        # ...then append the per-process table beneath it.
        $results |
            ConvertTo-Csv -NoTypeInformation |
            Add-Content -LiteralPath $Export -Encoding UTF8
        Write-Output "CSV written to: $Export"
    } catch {
        Write-Error "Failed to write CSV to '$Export': $_"
    }
}