[CmdletBinding()]
param(
    [string]$UserName = 'training.user'
)

try {
    $Result = [pscustomobject]@{
        UserName = $UserName
        WindowTitle = 'Training User Check'
        Status = 'WouldShowUserStatus'
        Enabled = $true
        TrainingOnly = $true
    }

    $Result

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
