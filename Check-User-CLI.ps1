[CmdletBinding()]
param(
    [string]$UserName = 'training.user'
)

try {
    $Status = [pscustomobject]@{
        UserName = $UserName
        AuthenticationState = 'WouldCheckCredentials'
        Group = 'Training-Operators'
        TrainingOnly = $true
    }

    $Status

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
