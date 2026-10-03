<#
.SYNOPSIS
Shows SecureString shape and boundary.

.DESCRIPTION
The script reports type details and states the training-only secret boundary.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # SecureString avoids plain text in memory display. It is not full secret management.
    $Secure = ConvertTo-SecureString -String 'demo-value' -AsPlainText -Force

    [pscustomobject]@{
        Stage = 'SecureStringShape'
        Type = $Secure.GetType().Name
        Length = $Secure.Length
        PlainTextWasTrainingOnly = $true
        SecretStoreRecommended = $true
        Note = 'SecureString is not a full secret-management boundary.'
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
