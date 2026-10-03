<#
.SYNOPSIS
Shows LDAP filter construction.

.DESCRIPTION
The script reports an escaped LDAP-style query and paging intent.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$SearchBase = 'OU=Training,DC=example,DC=invalid'
)

try {
    $EscapedUser = 'training.user'.Replace('(', '\28').Replace(')', '\29')
    $Filter = '(&(objectClass=user)(sAMAccountName={0}))' -f $EscapedUser
    $Query = [pscustomobject]@{
        Stage = 'BuildLdapQuery'
        SearchBase = $SearchBase
        Filter = $Filter
        EscapedSamAccountName = $EscapedUser
        ResultCount = 1
        WouldPageResults = $true
        TrainingOnly = $true
    }

    $Query

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
