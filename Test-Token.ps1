[CmdletBinding()]
param(
    [string]$Token = 'sample_training_token'
)

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PSFunctions.psm1') -Force -ErrorAction Stop

    $Result = Test-SampleToken -Token $Token
    $Result

    if (-not $Result.IsValid) {
        Write-Error -Message 'Training token failed the sample format check.' -ErrorAction Stop
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
