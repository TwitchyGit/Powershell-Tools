[CmdletBinding()]
param()

try {
    # Splatting names arguments once. Calls stay readable as parameter count grows.
    $SelectParams = @{
        First = 3
        Property = 'Name'
    }

    Get-Command -Noun Process | Select-Object @SelectParams
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
