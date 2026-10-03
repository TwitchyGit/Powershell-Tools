<#
.SYNOPSIS
Shows AD account state classification.

.DESCRIPTION
The script reports enabled, locked and expired state from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$SamAccountName = 'training.user'
)

try {
    $IsExpired = $SamAccountName -like '*expired*'
    $IsLocked = $SamAccountName -like '*locked*'
    $Account = [pscustomobject]@{
        SamAccountName = $SamAccountName
        DisplayName = 'Training User'
        Enabled = -not $IsExpired
        LockedOut = $IsLocked
        Expired = $IsExpired
        DistinguishedName = 'CN=Training User,OU=Training,DC=example,DC=invalid'
        Source = 'LocalTrainingData'
    }

    [pscustomobject]@{
        Stage = 'CheckAdAccount'
        SamAccountName = $Account.SamAccountName
        Enabled = $Account.Enabled
        LockedOut = $Account.LockedOut
        Expired = $Account.Expired
        Status = if ($Account.LockedOut) { 'Locked' } elseif ($Account.Expired) { 'Expired' } else { 'Ready' }
        Account = $Account
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
