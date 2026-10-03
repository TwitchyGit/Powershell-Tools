<#
.SYNOPSIS
Shows command-line user check shape.

.DESCRIPTION
The script reports local training validation state for a user name.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$UserName = 'training.user'
)

try {
    $Preflight = [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'UserName'
        Value = $UserName
        Passed = -not [string]::IsNullOrWhiteSpace($UserName)
    }

    $Status = [pscustomobject]@{
        Stage = 'CheckUserCli'
        UserName = $UserName
        AuthenticationState = 'WouldCheckCredentials'
        Group = 'Training-Operators'
        ResultCode = 0
        Result = 'WouldPass'
        TrainingOnly = $true
    }

    Write-Output -InputObject $Preflight
    Write-Output -InputObject $Status

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
