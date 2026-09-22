[CmdletBinding()]
param()

try {
    # for loop is useful when index value matters.
    $Names = 'Alpha', 'Beta', 'Gamma'

    for ($Index = 0; $Index -lt $Names.Count; $Index++) {
        [pscustomobject]@{
            Index = $Index
            Name = $Names[$Index]
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
