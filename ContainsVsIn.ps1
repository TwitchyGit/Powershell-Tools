[CmdletBinding()]
param()

try {
    # -contains reads collection first. -in reads candidate first. They test same membership relation.
    $Values = 'red', 'green', 'blue'

    [pscustomobject]@{
        ContainsGreen = $Values -contains 'green'
        GreenInValues = 'green' -in $Values
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
