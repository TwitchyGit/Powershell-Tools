[CmdletBinding()]
param()

try {
    # Arrays preserve order. Index zero is first item because PowerShell uses .NET collection indexing.
    $Names = @('Ada', 'Grace', 'Edsger')

    # Negative indexes count from end. This is PowerShell syntax over normal collection access.
    $FirstName = $Names[0]
    $LastName = $Names[-1]

    [pscustomobject]@{
        First = $FirstName
        Last = $LastName
        Count = $Names.Count
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
