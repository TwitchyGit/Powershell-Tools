[CmdletBinding()]
param()

try {
    $SetupScript = Join-Path -Path $PSScriptRoot -ChildPath 'Setup-GitRepoKeys.ps1'
    $PrepareScript = Join-Path -Path $PSScriptRoot -ChildPath 'Prepare-Deployment.ps1'
    $InvokeScript = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-Deployment.ps1'

    & $SetupScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error -Message 'Sample key setup failed.' -ErrorAction Stop
    }

    & $PrepareScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error -Message 'Sample deployment preparation failed.' -ErrorAction Stop
    }

    & $InvokeScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error -Message 'Sample deployment invocation failed.' -ErrorAction Stop
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
