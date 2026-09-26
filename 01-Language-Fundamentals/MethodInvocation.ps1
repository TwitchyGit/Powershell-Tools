<#
.SYNOPSIS
Shows direct method invocation.

.DESCRIPTION
The script reports string cleanup performed through .NET methods.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Objects expose methods. Method calls run .NET behavior directly.
    $Text = '  PowerShell 7.6  '
    $Clean = $Text.Trim().ToUpperInvariant()

    [pscustomobject]@{
        Stage = 'MethodInvocation'
        Original = $Text
        Clean = $Clean
        OriginalLength = $Text.Length
        CleanLength = $Clean.Length
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
