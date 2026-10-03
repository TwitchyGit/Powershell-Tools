<#
.SYNOPSIS
Shows safe WinRM credential decision logic.

.DESCRIPTION
The script reads endpoint fixture data and reports authentication guidance.

.NOTES
Kerberos with a domain hostname is preferred where domain membership supports it.
#>
[CmdletBinding()]
param(
    [string]
    $FixturePath = (Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/credential-samples.json')
)

try {
    $Fixture = Get-Content -Path $FixturePath -Raw | ConvertFrom-Json
    foreach ($Endpoint in $Fixture.Endpoints) {
        $Guidance = if ($Endpoint.Transport -eq 'Kerberos') {
            'Use domain hostname and Kerberos.'
        } elseif ($Endpoint.Transport -eq 'HTTPS') {
            'Use HTTPS with a trusted certificate. Scope TrustedHosts narrowly when required.'
        } else {
            'Review authentication method before use.'
        }

        [pscustomobject]@{
            Name = $Endpoint.Name
            HostName = $Endpoint.HostName
            Transport = $Endpoint.Transport
            RequiresTrustedHosts = [bool]$Endpoint.RequiresTrustedHosts
            Avoid = 'Basic, CredSSP and wildcard TrustedHosts'
            Guidance = $Guidance
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
