<#
.SYNOPSIS
Shows safe PSCredential inspection.

.DESCRIPTION
The script creates a synthetic PSCredential and returns safe metadata without exposing the password.

.NOTES
PSCredential carries a username and SecureString password. It does not authenticate until passed to a target.
#>
[CmdletBinding()]
param()

try {
    $SecurePassword = ConvertTo-SecureString -String 'SyntheticPassword-DoNotUse' -AsPlainText -Force
    $Credential = [pscredential]::new('TRAINING\svc-training', $SecurePassword)
    $NameParts = $Credential.UserName -split '\\', 2

    [pscustomobject]@{
        UserName = $Credential.UserName
        NameForm = 'NetBIOS'
        Domain = $NameParts[0]
        Account = $NameParts[1]
        PasswordStoredAs = $Credential.Password.GetType().Name
        SecretDisplayed = $false
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
