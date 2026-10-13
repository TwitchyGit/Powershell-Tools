<#
.SYNOPSIS
    Demonstrates security-hardening review from local sample findings.
.DESCRIPTION
    Reads synthetic findings and returns hardening actions. No policy, permission or certificate setting is changed.
.EXAMPLE
    ./Invoke-SecurityHardeningLesson.ps1
.EXAMPLE
    ./Invoke-SecurityHardeningLesson.ps1 -View Redacted
#>
[CmdletBinding()]
param(
    [ValidateSet('Actions', 'Redacted')]
    [string] $View = 'Actions',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-SecurityLessonData {
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

function ConvertTo-HardeningAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Finding
    )

    [pscustomobject]@{
        Area = $Finding.Area
        Severity = $Finding.Severity
        Action = switch ($Finding.Area) {
            'Secret' { 'Redact values and move secret retrieval to a vault boundary' }
            'TempFile' { 'Use a scoped temp path and remove files after use' }
            'Tls' { 'Keep certificate validation enabled and fix trust roots' }
            'Privilege' { 'Use least privilege for the operation being performed' }
            default { 'Review with the script owner' }
        }
    }
}

function ConvertTo-RedactedFinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Finding
    )

    [pscustomobject]@{
        Area = $Finding.Area
        Severity = $Finding.Severity
        SafeValue = if ($Finding.Area -eq 'Secret') { '[REDACTED]' } else { $Finding.Value }
    }
}

try {
    $Data = Get-SecurityLessonData -Path $DataPath
    switch ($View) {
        'Actions' {
            foreach ($Finding in $Data.Findings) {
                ConvertTo-HardeningAction -Finding $Finding
            }
        }
        'Redacted' {
            foreach ($Finding in $Data.Findings) {
                ConvertTo-RedactedFinding -Finding $Finding
            }
        }
    }

    exit 0
} catch {
    Write-Error -Message "Security hardening lesson failed. $($_.Exception.Message)"
    exit 1
}
