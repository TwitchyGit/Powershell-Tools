[CmdletBinding()]
param()

try {
    # SecureString avoids plain text in memory display. It is not full secret management.
    $Secure = ConvertTo-SecureString -String 'demo-value' -AsPlainText -Force

    [pscustomobject]@{
        Type = $Secure.GetType().Name
        Length = $Secure.Length
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
