<#
.SYNOPSIS
Shows certificate credential metadata.

.DESCRIPTION
The script reads synthetic certificate metadata and reports authentication-relevant fields.

.NOTES
Certificate authentication requires access to the private key, not just the public certificate.
#>
[CmdletBinding()]
param(
    [string]
    $FixturePath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/credential-samples.json')
)

try {
    $Fixture = Get-Content -Path $FixturePath -Raw | ConvertFrom-Json
    foreach ($Certificate in $Fixture.Certificates) {
        [pscustomobject]@{
            Subject = $Certificate.Subject
            Thumbprint = $Certificate.Thumbprint
            Store = $Certificate.Store
            HasPrivateKey = [bool]$Certificate.HasPrivateKey
            Exportable = [bool]$Certificate.Exportable
            LiveStoreChecked = $false
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
