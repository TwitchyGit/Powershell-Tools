Add-Type -AssemblyName System.DirectoryServices.Protocols

$server = "ldapdirectory.com"   # or "ldapuat.x.com:1389" if you want a specific port

# If you need a specific port, use this instead:
# $id = [System.DirectoryServices.Protocols.LdapDirectoryIdentifier]::new("ldapdirectory.com",1389,$false,$false)
# $connection = [System.DirectoryServices.Protocols.LdapConnection]::new($id)

$connection = [System.DirectoryServices.Protocols.LdapConnection]::new($server)
$connection.SessionOptions.ProtocolVersion = 3
$connection.AuthType = [System.DirectoryServices.Protocols.AuthType]::Negotiate

try {
    ##### 1. Ask RootDSE what naming contexts exist #####
    $rootReq = [System.DirectoryServices.Protocols.SearchRequest]::new(
        "",
        "(objectClass=*)",
        [System.DirectoryServices.Protocols.SearchScope]::Base,
        [string[]]@("namingContexts","defaultNamingContext")
    )

    $rootResp = [System.DirectoryServices.Protocols.SearchResponse]$connection.SendRequest($rootReq)

    $contexts = $rootResp.Entries[0].Attributes["namingContexts"].GetValues([string])
    Write-Host "Naming contexts from server:"
    $contexts | ForEach-Object { " - $_" }

    $default = $rootResp.Entries[0].Attributes["defaultNamingContext"].GetValues([string])
    Write-Host "Default NC:"
    $default

    ##### 2. Do a simple search directly under the first naming context #####
    $base = $contexts[0]   # pick whichever NC makes sense
    Write-Host "`nTesting base DN: '$base'"

    $req1 = [System.DirectoryServices.Protocols.SearchRequest]::new(
        $base,
        "(objectClass=*)",
        [System.DirectoryServices.Protocols.SearchScope]::OneLevel,
        [string[]]@("distinguishedName")
    )

    $resp1 = [System.DirectoryServices.Protocols.SearchResponse]$connection.SendRequest($req1)
    Write-Host "Entries returned under $base : $($resp1.Entries.Count)"

    # Show the first few DNs so we know the REAL structure
    $resp1.Entries |
        Select-Object -First 10 |
        ForEach-Object { "  DN: $($_.DistinguishedName)" }

    ##### 3. Now try your target base, but built under the naming context #####
    # Replace these with what you *think* the path is, but use the context from above.
    # Example only:
    $yourBase = "ou=person,ou=region,$base"
    Write-Host "`nTesting your base DN: '$yourBase'"

    $req2 = [System.DirectoryServices.Protocols.SearchRequest]::new(
        $yourBase,
        "(objectClass=*)",
        [System.DirectoryServices.Protocols.SearchScope]::Subtree,
        [string[]]@("uid","cn","employeeNumber")
    )

    $resp2 = [System.DirectoryServices.Protocols.SearchResponse]$connection.SendRequest($req2)
    Write-Host "Entries returned under $yourBase : $($resp2.Entries.Count)"

} catch [System.DirectoryServices.Protocols.LdapException] {
    Write-Host "LDAP error $($_.ErrorCode): $($_.Message)"
    if ($_.ServerErrorMessage) {
        Write-Host "ServerErrorMessage:"
        Write-Host $($_.ServerErrorMessage)
    }
} catch {
    Write-Host "Other error: $($_.Exception.Message)"
} finally {
    if ($connection) { $connection.Dispose() }
}
