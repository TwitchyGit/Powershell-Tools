[CmdletBinding()]
param()

try {
    # Double-quoted here-string expands variables. Single-quoted here-string keeps text literal.
    $Name = 'PowerShell'
    $Expanded = @"
Hello $Name
"@
    $Literal = @'
Hello $Name
'@

    [pscustomobject]@{
        Expanded = $Expanded.Trim()
        Literal = $Literal.Trim()
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
