[CmdletBinding()]
param(
    [string]$SamAccountName = 'training.user'
)

try {
    $Account = [pscustomobject]@{
        SamAccountName = $SamAccountName
        DisplayName = 'Training User'
        Enabled = $true
        DistinguishedName = 'CN=Training User,OU=Training,DC=example,DC=invalid'
        Source = 'LocalTrainingData'
    }

    $Account

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
