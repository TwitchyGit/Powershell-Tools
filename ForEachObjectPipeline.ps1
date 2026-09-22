[CmdletBinding()]
param()

try {
    # ForEach-Object runs once per pipeline input object. Current object is $_.
    1..5 | ForEach-Object {
        [pscustomobject]@{
            Input = $_
            Square = $_ * $_
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
