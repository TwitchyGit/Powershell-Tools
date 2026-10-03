[CmdletBinding()]
param()

try {
    # StrictMode catches uninitialized variables and other loose behaviors early.
    Set-StrictMode -Version Latest
    $Name = 'PowerShell'

    [pscustomobject]@{
        Name = $Name
        StrictMode = 'Latest'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
