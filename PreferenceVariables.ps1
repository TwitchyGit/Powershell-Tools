[CmdletBinding()]
param()

try {
    # Preference variables set default stream behavior in current scope.
    $VerbosePreference = 'Continue'
    Write-Verbose -Message 'Verbose output is enabled in this scope'

    'Done'
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
