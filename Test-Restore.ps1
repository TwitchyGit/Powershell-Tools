[CmdletBinding()]
param()

try {
    $ConfigureScript = Join-Path -Path $PSScriptRoot -ChildPath 'Configure.ps1'
    $InventoryScript = Join-Path -Path $PSScriptRoot -ChildPath 'Get-SafeInventory.ps1'
    $VerifyScript = Join-Path -Path $PSScriptRoot -ChildPath 'Verify-RestoredSafes.ps1'

    & $ConfigureScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error -Message 'Training restore configuration failed.' -ErrorAction Stop
    }

    & $InventoryScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error -Message 'Training safe inventory failed.' -ErrorAction Stop
    }

    & $VerifyScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error -Message 'Training restore verification failed.' -ErrorAction Stop
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
