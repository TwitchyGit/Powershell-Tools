<#
.SYNOPSIS
Shows expandable and literal here-strings.

.DESCRIPTION
The script reports how variable text is handled in each here-string form.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
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
        Stage = 'HereStrings'
        Expanded = $Expanded.Trim()
        Literal = $Literal.Trim()
        ExpandedLength = $Expanded.Trim().Length
        LiteralKeptVariableText = $Literal -like '*$Name*'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
