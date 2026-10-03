[CmdletBinding()]
param()

try {
    $Scripts = @(
        'Set-Conf.ps1'
        'Set-Conf-User.ps1'
        'AddGroup-Member.ps1'
        'PAS-CreateObjectList.ps1'
        'PAS-ProcessFailedObjects.ps1'
        'Scan-ADComputerOU.ps1'
        'AutosysRunfile.ps1'
    )

    foreach ($Script in $Scripts) {
        $ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath $Script
        & $ScriptPath
        if ($LASTEXITCODE -ne 0) {
            Write-Error -Message ('Training script failed: {0}' -f $Script) -ErrorAction Stop
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
