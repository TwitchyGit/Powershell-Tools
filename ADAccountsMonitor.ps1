[CmdletBinding()]
param()

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ADAccountsMonitor.psm1') -Force -ErrorAction Stop

    $Computers = Get-TrainingAdComputer
    $Results = foreach ($Computer in $Computers) {
        Test-TrainingAdComputer -Computer $Computer
    }

    $Results

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
