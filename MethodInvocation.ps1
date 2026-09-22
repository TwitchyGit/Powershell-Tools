[CmdletBinding()]
param()

try {
    # Objects expose methods. Method calls run .NET behavior directly.
    $Text = '  PowerShell 7.6  '
    $Clean = $Text.Trim().ToUpperInvariant()

    [pscustomobject]@{
        Original = $Text
        Clean = $Clean
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
