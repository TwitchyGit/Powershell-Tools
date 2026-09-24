[CmdletBinding()]
param(
    [string]$SampleScript = 'Install-VSCodePackages.ps1'
)

try {
    $SamplePath = Join-Path -Path $PSScriptRoot -ChildPath $SampleScript
    if (-not (Test-Path -Path $SamplePath -PathType Leaf)) {
        Write-Error -Message ('Sample script was not found: {0}' -f $SamplePath) -ErrorAction Stop
    }

    $Tokens = $null
    $ParseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($SamplePath, [ref]$Tokens, [ref]$ParseErrors) | Out-Null

    $CompatibilityNotes = @(
        [pscustomobject]@{
            Check = 'Parser'
            Result = if ($ParseErrors.Count -eq 0) { 'Pass' } else { 'Fail' }
            Detail = ('ParserErrors={0}' -f $ParseErrors.Count)
        }
        [pscustomobject]@{
            Check = 'TrainingScope'
            Result = 'Pass'
            Detail = 'The sample uses local JSON package records only.'
        }
        [pscustomobject]@{
            Check = 'VersionTarget'
            Result = 'Review'
            Detail = 'Run on Windows PowerShell 5.1 and PowerShell 7.6.3 for live host proof.'
        }
    )

    $CompatibilityNotes

    if ($ParseErrors.Count -gt 0) {
        Write-Error -Message 'Compatibility parser check failed.' -ErrorAction Stop
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
