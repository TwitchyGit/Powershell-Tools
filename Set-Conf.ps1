[CmdletBinding()]
param(
    [string]$Name = 'RunMode',

    [string]$Value = 'Training'
)

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ConfigModule.psm1') -Force -ErrorAction Stop

    $Result = Set-TrainingConfiguration -Name $Name -Value $Value
    $Result

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
