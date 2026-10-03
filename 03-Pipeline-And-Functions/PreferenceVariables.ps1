<#
.SYNOPSIS
Shows scoped preference variable behavior.

.DESCRIPTION
The script reports verbose preference before and during the sample.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # Preference variables set default stream behavior in current scope.
    $PreviousVerbosePreference = $VerbosePreference
    $VerbosePreference = 'Continue'
    Write-Verbose -Message 'Verbose output is enabled in this scope'

    [pscustomobject]@{
        Stage = 'PreferenceScope'
        PreviousVerbosePreference = $PreviousVerbosePreference
        CurrentVerbosePreference = $VerbosePreference
        Result = 'Done'
    }

    $VerbosePreference = $PreviousVerbosePreference
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
