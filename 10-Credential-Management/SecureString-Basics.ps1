<#
.SYNOPSIS
Shows local SecureString behavior.

.DESCRIPTION
The script creates a SecureString from synthetic text and reports safe metadata about its use.

.NOTES
SecureString reduces casual display risk. It is not a vault, access-control model or rotation process.
#>
[CmdletBinding()]
param()

try {
    $PlainValue = 'SyntheticPassword-DoNotUse'
    $SecureValue = ConvertTo-SecureString -String $PlainValue -AsPlainText -Force
    $Credential = [pscredential]::new('training\svc-training', $SecureValue)

    [pscustomobject]@{
        UserName = $Credential.UserName
        SecureStringType = $SecureValue.GetType().FullName
        LengthAvailable = $SecureValue.Length -gt 0
        PlainTextReturned = $false
        Boundary = 'Local object demonstration only'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
