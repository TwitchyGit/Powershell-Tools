[CmdletBinding()]
param()

try {
    # Native tools set LASTEXITCODE. PowerShell cmdlets use error records instead.
    if ($IsWindows) {
        cmd.exe /c exit 7
    } else {
        /bin/sh -c 'exit 7'
    }

    [pscustomobject]@{
        LastExitCode = $LASTEXITCODE
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
