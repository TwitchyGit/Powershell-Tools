<#
.SYNOPSIS
Shows logging-safe API token handling.

.DESCRIPTION
The script reads synthetic token metadata from the fixture file and returns redacted summaries.

.NOTES
Bearer tokens should be treated as credentials until expiry and revocation are confirmed.
#>
[CmdletBinding()]
param(
    [string]
    $FixturePath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/credential-samples.json')
)

try {
    $Fixture = Get-Content -Path $FixturePath -Raw | ConvertFrom-Json
    foreach ($Token in $Fixture.Tokens) {
        $Expiry = [datetime]::Parse($Token.ExpiresUtc).ToUniversalTime()
        [pscustomobject]@{
            Name = $Token.Name
            Prefix = $Token.Prefix
            Scope = $Token.Scope
            ExpiresUtc = $Expiry.ToString('u')
            RedactedValue = '{token redacted}'
            SecretMaterialReturned = $false
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
