[CmdletBinding()]
param(
    [string]$OrganizationalUnit = 'OU=Training,DC=example,DC=invalid'
)

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ADAccountsMonitor.psm1') -Force -ErrorAction Stop

    $Computers = Get-TrainingAdComputer -OrganizationalUnit $OrganizationalUnit
    $Computers | ForEach-Object {
        Test-TrainingAdComputer -Computer $_
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
