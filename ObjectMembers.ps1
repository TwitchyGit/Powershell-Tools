[CmdletBinding()]
param()

try {
    # Get-Member shows properties and methods on objects. It teaches shape before use.
    'PowerShell' |
        Get-Member |
        Where-Object -Property MemberType -eq 'Method' |
        Select-Object -First 5 -Property Name, MemberType

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
