[CmdletBinding()]
param(
    [string]$SearchBase = 'OU=Training,DC=example,DC=invalid'
)

try {
    $Query = [pscustomobject]@{
        SearchBase = $SearchBase
        Filter = '(&(objectClass=user)(sAMAccountName=training.user))'
        ResultCount = 1
        TrainingOnly = $true
    }

    $Query

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
