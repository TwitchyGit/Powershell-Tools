<#
.SYNOPSIS
    Demonstrates REST response handling from local sample responses.
.DESCRIPTION
    Reads synthetic HTTP responses and classifies them into parse, reauth, retry and fail decisions. No network
    request is made.
.EXAMPLE
    ./Invoke-RestResilienceLesson.ps1
.EXAMPLE
    ./Invoke-RestResilienceLesson.ps1 -View RetryPlan
#>
[CmdletBinding()]
param(
    [ValidateSet('Assessment', 'RetryPlan')]
    [string] $View = 'Assessment',

    [string] $DataPath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/sample-data.json')
)

function Get-RestLessonData {
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

function Test-RestResponseShape {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Request
    )

    $JsonValid = $false
    if ($Request.ContentType -eq 'application/json') {
        try {
            $null = $Request.Body | ConvertFrom-Json
            $JsonValid = $true
        } catch {
            $JsonValid = $false
        }
    }

    $Decision = switch ($Request.StatusCode) {
        200 {
            if ($Request.ContentType -ne 'application/json') {
                'FailContentType'
            } elseif (-not $JsonValid) {
                'FailMalformedJson'
            } else {
                'UseResponse'
            }
        }
        401 { 'RefreshToken' }
        429 { 'RetryAfterDelay' }
        default { 'FailStatusCode' }
    }

    [pscustomobject]@{
        Name = $Request.Name
        StatusCode = $Request.StatusCode
        ContentType = $Request.ContentType
        JsonValid = $JsonValid
        Decision = $Decision
    }
}

function New-RetryPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject[]] $Requests
    )

    foreach ($Request in $Requests) {
        $Assessment = Test-RestResponseShape -Request $Request
        [pscustomobject]@{
            Name = $Request.Name
            Decision = $Assessment.Decision
            WaitSeconds = if ($Assessment.Decision -eq 'RetryAfterDelay') { $Request.RetryAfterSeconds } else { 0 }
            SanitizedDetail = "Status $($Request.StatusCode), content type $($Request.ContentType)"
        }
    }
}

try {
    $Data = Get-RestLessonData -Path $DataPath
    switch ($View) {
        'Assessment' {
            foreach ($Request in $Data.Requests) {
                Test-RestResponseShape -Request $Request
            }
        }
        'RetryPlan' {
            New-RetryPlan -Requests $Data.Requests
        }
    }

    exit 0
} catch {
    Write-Error -Message "REST resilience lesson failed. $($_.Exception.Message)"
    exit 1
}
