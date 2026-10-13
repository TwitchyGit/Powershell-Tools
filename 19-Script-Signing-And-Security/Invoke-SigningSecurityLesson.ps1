<#
.SYNOPSIS
    Demonstrates script-signing and execution-policy checks from sample data.
.DESCRIPTION
    Reads synthetic script-signing records and returns local policy decisions. No certificate store is queried and no
    script is signed or executed.
.EXAMPLE
    ./Invoke-SigningSecurityLesson.ps1
.EXAMPLE
    ./Invoke-SigningSecurityLesson.ps1 -View Policy
#>
[CmdletBinding()]
param(
    [ValidateSet('Assessment', 'Policy')]
    [string] $View = 'Assessment',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-SigningSecurityData {
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

function Test-TrainingSignatureRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Script,

        [Parameter(Mandatory = $true)]
        [string[]] $AllowedPublisher
    )

    $TrustedPublisher = $Script.Publisher -in $AllowedPublisher
    $CanRun = $Script.SignatureStatus -eq 'Valid' -and $TrustedPublisher -and $Script.HashMatches

    [pscustomobject]@{
        Path = $Script.Path
        SignatureStatus = $Script.SignatureStatus
        TrustedPublisher = $TrustedPublisher
        HashMatches = [bool] $Script.HashMatches
        TrainingDecision = if ($CanRun) { 'Allowed' } else { 'ReviewRequired' }
    }
}

function New-PolicySummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]] $Scripts
    )

    $Scripts |
        Group-Object -Property ExecutionPolicy |
        Sort-Object -Property Name |
        ForEach-Object {
            [pscustomobject]@{
                ExecutionPolicy = $_.Name
                ScriptCount = $_.Count
                TrainingMeaning = switch ($_.Name) {
                    'AllSigned' { 'Every script should have a trusted signature' }
                    'RemoteSigned' { 'Downloaded scripts need a trusted signature' }
                    default { 'Policy needs local review before use' }
                }
            }
        }
}

try {
    $Data = Get-SigningSecurityData -Path $DataPath
    switch ($View) {
        'Assessment' {
            foreach ($Script in $Data.Scripts) {
                Test-TrainingSignatureRecord -Script $Script -AllowedPublisher $Data.AllowedPublishers
            }
        }
        'Policy' {
            New-PolicySummary -Scripts $Data.Scripts
        }
    }

    exit 0
} catch {
    Write-Error -Message "Script-signing lesson failed. $($_.Exception.Message)"
    exit 1
}
