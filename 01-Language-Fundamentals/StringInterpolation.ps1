<#
.SYNOPSIS
Shows string interpolation and formatting.

.DESCRIPTION
The script reports expandable string output and format-operator output.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # $() disambiguates expressions inside expandable strings.
    $Name = 'PowerShell'
    $Version = [version]'7.6'
    $Message = "$Name major version is $($Version.Major)"

    [pscustomobject]@{
        Stage = 'StringInterpolation'
        Message = $Message
        FormatMessage = '{0} minor version is {1}' -f $Name, $Version.Minor
    }
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
