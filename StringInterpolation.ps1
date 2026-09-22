[CmdletBinding()]
param()

try {
    # $() disambiguates expressions inside expandable strings.
    $Name = 'PowerShell'
    $Version = [version]'7.6'
    $Message = "$Name major version is $($Version.Major)"

    $Message
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
