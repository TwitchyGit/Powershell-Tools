[CmdletBinding()]
param()

try {
    # -match sets $Matches for current scope when pattern succeeds.
    $Text = 'PowerShell 7.6'
    $Found = $Text -match 'PowerShell (?<Version>\d+\.\d+)'

    [pscustomobject]@{
        Found = $Found
        Version = $Matches.Version
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
