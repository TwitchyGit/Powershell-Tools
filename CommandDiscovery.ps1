[CmdletBinding()]
param()

try {
    # Get-Command queries available commands. Verb and noun filters keep discovery precise.
    Get-Command -Verb Get -Noun Process |
        Select-Object -Property Name, CommandType, Source

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
