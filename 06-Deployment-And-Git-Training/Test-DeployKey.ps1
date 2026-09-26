<#
.SYNOPSIS
Shows deployment token validation.

.DESCRIPTION
The script reports whether a local training token matches expected shape.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$Token = 'sample_training_token'
)

try {
    $SharedModule = Join-Path -Path $PSScriptRoot -ChildPath '../05-Modules-And-Configuration/PSFunctions.psm1'
    Import-Module -Name $SharedModule -Force -ErrorAction Stop

    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'TokenProvided'
        Value = $Token.Length
        Passed = -not [string]::IsNullOrWhiteSpace($Token)
    }

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
