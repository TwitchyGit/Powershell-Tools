[CmdletBinding()]
param()

try {
    # Range operator creates integer indexes. PowerShell returns matching elements in same order.
    $Numbers = 10, 20, 30, 40, 50
    $Middle = $Numbers[1..3]

    # Reversed ranges work too. Result order follows range order not original array order.
    $Reverse = $Numbers[3..1]

    [pscustomobject]@{
        Middle = $Middle -join ', '
        Reverse = $Reverse -join ', '
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
