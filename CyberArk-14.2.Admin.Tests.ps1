#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$TestConfig,

    [Parameter(Mandatory = $true)]
    [System.Management.Automation.PSCredential]$AdminCredential
)

Describe ([string]$TestConfig.AdminSuiteName) -Tag 'Integration', 'CyberArk14.2', 'AdministratorRegression', 'DestructiveTestObjectsOnly' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # One random suffix prevents two approved regression runs colliding with each other.
        $script:BaseUrl = ([string]$TestConfig.PVWAUrl).TrimEnd('/')
        $runSuffix = '{0}-{1}' -f (Get-Date -Format 'MMddHHmmss'), (Get-Random -Minimum 1000 -Maximum 9999)
        $groupBaseName = '{0}-{1}-G' -f $TestConfig.TestObjectPrefix, $runSuffix

        # Creation flags ensure cleanup can target only objects made by this invocation.
        $script:State = [ordered]@{
            Token                      = $null
            UserName                   = '{0}-{1}-AU' -f $TestConfig.TestObjectPrefix, $runSuffix
            UserId                     = $null
            UserCreated                = $false
            GroupName                  = $groupBaseName
            UpdatedGroupName           = '{0}-{1}' -f $groupBaseName, $TestConfig.UpdatedAdminGroupNameSuffix
            GroupId                    = $null
            GroupCreated               = $false
            GroupMemberCreated         = $false
            ApplicationId              = '{0}-{1}-APP' -f $TestConfig.TestObjectPrefix, $runSuffix
            ApplicationCreated         = $false
            ApplicationAuthenticationId = $null
            ApplicationAuthenticationCreated = $false
        }

        function Get-HttpStatusCode {
            param([System.Management.Automation.ErrorRecord]$ErrorRecord)

            # Prefer status preserved by our sanitised exception before inspecting native responses.
            if ($null -ne $ErrorRecord.Exception.Data['StatusCode']) {
                return [int]$ErrorRecord.Exception.Data['StatusCode']
            }
            if ($null -ne $ErrorRecord.Exception.Response -and $null -ne $ErrorRecord.Exception.Response.StatusCode) {
                return [int]$ErrorRecord.Exception.Response.StatusCode
            }
            return 0
        }

        function Invoke-CARestMethod {
            [CmdletBinding()]
            param(
                [Parameter(Mandatory = $true)]
                [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
                [string]$Method,

                [Parameter(Mandatory = $true)]
                [string]$Path,

                [Parameter()]
                [AllowNull()]
                [object]$Body,

                [Parameter()]
                [switch]$NoAuthentication
            )

            # Shared request construction makes method and route behaviour comparable across releases.
            $relativePath = $Path.TrimStart('/')
            $request = @{
                Uri         = "$script:BaseUrl/$relativePath"
                Method      = $Method
                ContentType = 'application/json'
                ErrorAction = 'Stop'
            }

            if ($PSVersionTable.PSVersion.Major -le 5) {
                # Windows PowerShell 5.1 needs this to avoid its Internet Explorer dependency.
                $request.UseBasicParsing = $true
            }

            if (-not $NoAuthentication) {
                if ([string]::IsNullOrWhiteSpace([string]$script:State.Token)) {
                    throw 'No CyberArk administrator authorization token is available.'
                }
                $request.Headers = @{ Authorization = $script:State.Token }
            }

            if ($PSBoundParameters.ContainsKey('Body')) {
                # A generous depth preserves nested CyberArk permission and authentication objects.
                $request.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
            }

            # The trace intentionally omits headers and bodies because either can contain secrets.
            $displayRoute = "/$relativePath"
            Write-Host ("       [API] RUN  {0,-6} {1}" -f $Method, $displayRoute)
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

            try {
                $response = Invoke-RestMethod @request
                $stopwatch.Stop()
                Write-Host ("       [API] PASS {0,-6} {1} ({2} ms)" -f $Method, $displayRoute, $stopwatch.ElapsedMilliseconds)
                return $response
            }
            catch {
                $stopwatch.Stop()
                $statusCode = Get-HttpStatusCode -ErrorRecord $_
                $serverMessage = [string]$_.ErrorDetails.Message
                if ([string]::IsNullOrWhiteSpace($serverMessage)) {
                    $serverMessage = [string]$_.Exception.Message
                }

                $statusLabel = if ($statusCode -gt 0) { "HTTP $statusCode" } else { 'no HTTP status' }
                Write-Host ("       [API] FAIL {0,-6} {1} ({2}; {3} ms)" -f $Method, $displayRoute, $statusLabel, $stopwatch.ElapsedMilliseconds)

                $message = "CyberArk REST $Method /$relativePath failed"
                if ($statusCode -gt 0) {
                    $message += " with HTTP $statusCode"
                }
                if (-not [string]::IsNullOrWhiteSpace($serverMessage)) {
                    $message += ": $serverMessage"
                }

                # Replacing the exception preserves diagnostics without exposing the request headers.
                $sanitisedException = New-Object System.Exception($message, $_.Exception)
                $sanitisedException.Data['StatusCode'] = $statusCode
                throw $sanitisedException
            }
        }

        function Get-TokenFromLogonResponse {
            param([AllowNull()][object]$Response)

            # Classic and newer logon routes can return either a string or a named token property.
            if ($Response -is [string]) {
                return $Response.Trim('"')
            }
            foreach ($propertyName in @('CyberArkLogonResult', 'Token', 'access_token')) {
                if ($null -ne $Response -and $null -ne $Response.PSObject.Properties[$propertyName]) {
                    return [string]$Response.$propertyName
                }
            }
            return $null
        }

        function Get-FirstPropertyValue {
            param(
                [AllowNull()][object]$InputObject,
                [Parameter(Mandatory = $true)][string[]]$PropertyNames
            )

            # CyberArk response casing differs between classic and Gen2 APIs, so accept known variants.
            foreach ($propertyName in $PropertyNames) {
                if ($null -ne $InputObject -and $null -ne $InputObject.PSObject.Properties[$propertyName]) {
                    return $InputObject.$propertyName
                }
            }
            return $null
        }

        function New-TestPassword {
            param([int]$Length)

            if ($Length -lt $TestConfig.MinimumPasswordLength) {
                throw "TestPasswordLength must be at least $($TestConfig.MinimumPasswordLength)."
            }

            # The prefix guarantees common complexity classes while the random tail prevents reuse.
            $characters = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%_-+'
            $randomPart = -join (1..($Length - 4) | ForEach-Object {
                $characters[(Get-Random -Minimum 0 -Maximum $characters.Length)]
            })
            return "Aa1!$randomPart"
        }

        function Test-DeletedRoute {
            param([Parameter(Mandatory = $true)][string]$Path)

            try {
                # Returning 200 makes the Pester assertion fail if deletion did not take effect.
                $null = Invoke-CARestMethod -Method GET -Path $Path
                return 200
            }
            catch {
                return Get-HttpStatusCode -ErrorRecord $_
            }
        }

        function Remove-AdministratorTestObjects {
            # Cleanup runs in dependency order and never searches for or removes pre-existing objects.
            if ([string]::IsNullOrWhiteSpace([string]$script:State.Token)) {
                return
            }

            if ($script:State.ApplicationAuthenticationCreated) {
                try {
                    $app = [uri]::EscapeDataString([string]$script:State.ApplicationId)
                    if ($null -eq $script:State.ApplicationAuthenticationId) {
                        # Recover the generated method's ID if its test failed after the POST succeeded.
                        $response = Invoke-CARestMethod -Method GET -Path "WebServices/PIMServices.svc/Applications/$app/Authentications/"
                        $authentications = @(Get-FirstPropertyValue -InputObject $response -PropertyNames @('authentication', 'Authentication'))
                        $generatedAuthentication = @($authentications | Where-Object {
                            (Get-FirstPropertyValue -InputObject $_ -PropertyNames @('AuthValue', 'authValue')) -eq $TestConfig.AdminApplicationMachineAddress
                        }) | Select-Object -First 1
                        $script:State.ApplicationAuthenticationId = Get-FirstPropertyValue -InputObject $generatedAuthentication -PropertyNames @('AuthID', 'authID', 'id', 'ID')
                    }

                    if ($null -ne $script:State.ApplicationAuthenticationId) {
                        $auth = [uri]::EscapeDataString([string]$script:State.ApplicationAuthenticationId)
                        $null = Invoke-CARestMethod -Method DELETE -Path "WebServices/PIMServices.svc/Applications/$app/Authentications/$auth/"
                    }
                }
                catch {
                    Write-Warning "Cleanup could not remove the disposable application authentication: $($_.Exception.Message)"
                }
            }

            if ($script:State.ApplicationCreated) {
                try {
                    $app = [uri]::EscapeDataString([string]$script:State.ApplicationId)
                    $null = Invoke-CARestMethod -Method DELETE -Path "WebServices/PIMServices.svc/Applications/$app/"
                }
                catch {
                    Write-Warning "Cleanup could not remove test application '$($script:State.ApplicationId)': $($_.Exception.Message)"
                }
            }

            if ($script:State.GroupMemberCreated -and $script:State.GroupCreated) {
                try {
                    $member = [uri]::EscapeDataString([string]$script:State.UserName)
                    $null = Invoke-CARestMethod -Method DELETE -Path "API/UserGroups/$($script:State.GroupId)/members/$member/"
                }
                catch {
                    Write-Warning "Cleanup could not remove the disposable group member: $($_.Exception.Message)"
                }
            }

            if ($script:State.GroupCreated -and $null -ne $script:State.GroupId) {
                try {
                    $null = Invoke-CARestMethod -Method DELETE -Path "API/UserGroups/$($script:State.GroupId)"
                }
                catch {
                    Write-Warning "Cleanup could not remove test group '$($script:State.GroupName)': $($_.Exception.Message)"
                }
            }

            if ($script:State.UserCreated -and $null -ne $script:State.UserId) {
                try {
                    $null = Invoke-CARestMethod -Method DELETE -Path "API/Users/$($script:State.UserId)"
                }
                catch {
                    Write-Warning "Cleanup could not remove test user '$($script:State.UserName)': $($_.Exception.Message)"
                }
            }
        }
    }

    AfterAll {
        # Best-effort cleanup still runs after a failed assertion so test debris is minimised.
        Remove-AdministratorTestObjects

        if (-not [string]::IsNullOrWhiteSpace([string]$script:State.Token)) {
            try {
                $null = Invoke-CARestMethod -Method POST -Path 'API/Auth/Logoff'
            }
            catch {
                Write-Warning "CyberArk logoff failed: $($_.Exception.Message)"
            }
        }

        $script:State.Token = $null
    }

    Context 'Authentication and administrator identity' {
        It 'authenticates once with the supplied administrator credential' {
            # The password exists in plain text only for the duration of the logon request.
            $plainPassword = $AdminCredential.GetNetworkCredential().Password
            $logonBody = [ordered]@{
                username          = $AdminCredential.UserName
                password          = $plainPassword
                concurrentSession = [bool]$TestConfig.ConcurrentSession
            }

            try {
                $response = Invoke-CARestMethod -Method POST -Path "API/Auth/$($TestConfig.AuthenticationType)/Logon" -Body $logonBody -NoAuthentication
                $script:State.Token = Get-TokenFromLogonResponse -Response $response
            }
            finally {
                $logonBody.password = $null
                $plainPassword = $null
            }

            $script:State.Token | Should -Not -BeNullOrEmpty
        }

        It 'returns the intended administrator through the current-user API' {
            # A valid token alone does not prove that the expected administrative identity logged on.
            $currentUser = Invoke-CARestMethod -Method GET -Path 'API/CurrentUser'
            $currentUser.username | Should -Be $AdminCredential.UserName
        }
    }

    Context 'Read-only administrative inventory' {
        It 'returns PVWA server information' {
            # Server metadata provides a useful release fingerprint for baseline comparison.
            Invoke-CARestMethod -Method GET -Path 'api/server' | Should -Not -BeNullOrEmpty
        }

        It 'lists configured authentication methods' {
            # Authentication inventory detects route, schema and authorisation regressions without edits.
            Invoke-CARestMethod -Method GET -Path 'api/Configuration/AuthenticationMethods/' | Should -Not -BeNullOrEmpty
        }

        It 'returns the component health summary' -Skip:(-not [bool]$TestConfig.TestSystemHealth) {
            # Health is read-only but can be disabled for Vaults without component monitoring access.
            Invoke-CARestMethod -Method GET -Path 'api/ComponentsMonitoringSummary' | Should -Not -BeNullOrEmpty
        }

        It 'returns configured component health details' -Skip:(-not [bool]$TestConfig.TestSystemHealth) {
            # Check only configured component IDs because not every deployment installs every component.
            foreach ($componentId in @($TestConfig.ComponentDetailIds)) {
                $escapedId = [uri]::EscapeDataString([string]$componentId)
                Invoke-CARestMethod -Method GET -Path "api/ComponentsMonitoringDetails/$escapedId" | Should -Not -BeNullOrEmpty
            }
        }

        It 'lists users available to the administrator' {
            # This exercises the collection contract without changing any existing user.
            Invoke-CARestMethod -Method GET -Path 'API/Users' | Should -Not -BeNullOrEmpty
        }

        It 'lists Vault user groups' {
            # Group inventory is the read-side baseline for the disposable lifecycle below.
            Invoke-CARestMethod -Method GET -Path 'API/UserGroups' | Should -Not -BeNullOrEmpty
        }

        It 'lists Safes available to the administrator' {
            # Existing Safe details remain untouched; only the collection route is exercised here.
            Invoke-CARestMethod -Method GET -Path 'API/Safes' | Should -Not -BeNullOrEmpty
        }

        It 'lists accounts available to the administrator' {
            # Account inventory validates the common administrative search route without secret retrieval.
            Invoke-CARestMethod -Method GET -Path 'API/Accounts?limit=1' | Should -Not -BeNullOrEmpty
        }

        It 'lists platform summaries' {
            # Platform summary access is safe to baseline because this call does not export or edit a platform.
            Invoke-CARestMethod -Method GET -Path 'API/Platforms' | Should -Not -BeNullOrEmpty
        }

        It 'lists target platforms' {
            # The target-platform collection detects schema changes used by platform tooling.
            Invoke-CARestMethod -Method GET -Path 'API/Platforms/targets' | Should -Not -BeNullOrEmpty
        }

        It 'reads the configured account platform' {
            # Reuse the platform configured for the User/Safe suite so no second platform ID can drift.
            $platformId = [uri]::EscapeDataString([string]$TestConfig.TestPlatformId)
            Invoke-CARestMethod -Method GET -Path "API/Platforms/$platformId/" | Should -Not -BeNullOrEmpty
        }

        It 'lists PSM connection components' -Skip:(-not [bool]$TestConfig.TestPSMConnectorInventory) {
            # Inventory is enough to detect API breakage without importing or updating shared connectors.
            Invoke-CARestMethod -Method GET -Path 'API/PSM/Connectors' | Should -Not -BeNullOrEmpty
        }

        It 'lists PSM servers' -Skip:(-not [bool]$TestConfig.TestPSMConnectorInventory) {
            # Server inventory verifies the companion PSM route without changing a server definition.
            Invoke-CARestMethod -Method GET -Path 'API/PSM/Servers' | Should -Not -BeNullOrEmpty
        }

        It 'lists LDAP directory definitions' -Skip:(-not [bool]$TestConfig.TestLDAPDirectoryInventory) {
            # This is opt-in because a local-only Vault can legitimately have no LDAP integration.
            Invoke-CARestMethod -Method GET -Path 'api/Configuration/LDAP/Directories' | Should -Not -BeNullOrEmpty
        }

        It 'lists live PSM sessions' -Skip:(-not [bool]$TestConfig.TestLiveSessionInventory) {
            # Monitoring rights are deployment-specific, so the read-only route is opt-in by default.
            Invoke-CARestMethod -Method GET -Path 'API/LiveSessions?Limit=1' | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Disposable Vault group lifecycle' {
        It 'creates a disposable local Vault user for group membership' {
            # The suite never borrows an existing user because that would alter real group membership.
            $testPassword = New-TestPassword -Length ([int]$TestConfig.TestPasswordLength)
            $body = [ordered]@{
                username              = $script:State.UserName
                initialPassword       = $testPassword
                userType              = [string]$TestConfig.UserType
                enableUser            = $true
                changePassOnNextLogon = $false
                passwordNeverExpires  = $false
                location              = [string]$TestConfig.UserLocation
                authenticationMethod  = @('AuthTypePass')
                personalDetails       = [ordered]@{
                    firstName = [string]$TestConfig.AdminUserFirstName
                    lastName  = [string]$TestConfig.TestUserLastName
                }
            }

            try {
                $createdUser = Invoke-CARestMethod -Method POST -Path 'API/Users' -Body $body
                $script:State.UserCreated = $true
                $script:State.UserId = Get-FirstPropertyValue -InputObject $createdUser -PropertyNames @('id', 'ID')
            }
            finally {
                $body.initialPassword = $null
                $testPassword = $null
            }

            $script:State.UserId | Should -Not -BeNullOrEmpty
            $createdUser.username | Should -Be $script:State.UserName
        }

        It 'creates a disposable Vault group' {
            # The description identifies the purpose if cleanup needs manual investigation.
            $body = [ordered]@{
                groupName  = $script:State.GroupName
                description = [string]$TestConfig.AdminGroupDescription
                location   = [string]$TestConfig.UserLocation
            }

            $createdGroup = Invoke-CARestMethod -Method POST -Path 'API/UserGroups' -Body $body
            $script:State.GroupCreated = $true
            $script:State.GroupId = Get-FirstPropertyValue -InputObject $createdGroup -PropertyNames @('id', 'ID', 'groupID', 'GroupID')

            $script:State.GroupId | Should -Not -BeNullOrEmpty
            (Get-FirstPropertyValue -InputObject $createdGroup -PropertyNames @('groupName', 'GroupName')) | Should -Be $script:State.GroupName
        }

        It 'reads the disposable Vault group by ID' {
            # ID-based reads verify that create output can drive later lifecycle calls.
            $group = Invoke-CARestMethod -Method GET -Path "API/UserGroups/$($script:State.GroupId)/"
            (Get-FirstPropertyValue -InputObject $group -PropertyNames @('groupName', 'GroupName')) | Should -Be $script:State.GroupName
        }

        It 'updates the disposable Vault group name' {
            # Renaming only the generated group gives PUT coverage without touching shared authorisation.
            $body = @{ groupName = $script:State.UpdatedGroupName }
            $null = Invoke-CARestMethod -Method PUT -Path "API/UserGroups/$($script:State.GroupId)" -Body $body
            $updatedGroup = Invoke-CARestMethod -Method GET -Path "API/UserGroups/$($script:State.GroupId)/"

            (Get-FirstPropertyValue -InputObject $updatedGroup -PropertyNames @('groupName', 'GroupName')) | Should -Be $script:State.UpdatedGroupName
        }

        It 'adds the disposable user to the disposable Vault group' {
            # Both sides are test objects, so no real user's effective access can change.
            $body = [ordered]@{
                memberId   = $script:State.UserName
                memberType = [string]$TestConfig.AdminGroupMemberType
            }
            $null = Invoke-CARestMethod -Method POST -Path "API/UserGroups/$($script:State.GroupId)/Members" -Body $body
            $script:State.GroupMemberCreated = $true

            $groupWithMembers = Invoke-CARestMethod -Method GET -Path "API/UserGroups/$($script:State.GroupId)/?includeMembers=true"
            ($groupWithMembers | ConvertTo-Json -Depth 20) | Should -Match ([regex]::Escape($script:State.UserName))
        }

        It 'removes the disposable user from the disposable Vault group' {
            # Explicit member deletion exercises the inverse route before the group itself is removed.
            $member = [uri]::EscapeDataString([string]$script:State.UserName)
            $null = Invoke-CARestMethod -Method DELETE -Path "API/UserGroups/$($script:State.GroupId)/members/$member/"
            $script:State.GroupMemberCreated = $false

            $groupWithMembers = Invoke-CARestMethod -Method GET -Path "API/UserGroups/$($script:State.GroupId)/?includeMembers=true"
            ($groupWithMembers | ConvertTo-Json -Depth 20) | Should -Not -Match ([regex]::Escape($script:State.UserName))
        }

        It 'deletes the disposable Vault group and verifies it is gone' {
            # Delete by captured ID so a similarly named pre-existing group can never be selected.
            $groupPath = "API/UserGroups/$($script:State.GroupId)"
            $null = Invoke-CARestMethod -Method DELETE -Path $groupPath
            $script:State.GroupCreated = $false

            Test-DeletedRoute -Path "$groupPath/" | Should -Be $TestConfig.ExpectedMissingStatus
        }

        It 'deletes the disposable group user and verifies it is gone' {
            # The generated user is removed after membership tests no longer depend on it.
            $userPath = "API/Users/$($script:State.UserId)"
            $null = Invoke-CARestMethod -Method DELETE -Path $userPath
            $script:State.UserCreated = $false

            Test-DeletedRoute -Path $userPath | Should -Be $TestConfig.ExpectedMissingStatus
        }
    }

    Context 'Disposable AAM application lifecycle' {
        It 'creates a disposable AAM application' -Skip:(-not [bool]$TestConfig.TestAAMApplicationCrud) {
            # The application has no account access and exists only to validate classic API compatibility.
            $body = @{
                application = [ordered]@{
                    AppID               = $script:State.ApplicationId
                    Description         = [string]$TestConfig.AdminApplicationDescription
                    Location            = [string]$TestConfig.AdminApplicationLocation
                    AccessPermittedFrom = [int]$TestConfig.AdminApplicationAccessFrom
                    AccessPermittedTo   = [int]$TestConfig.AdminApplicationAccessTo
                    Disabled            = $false
                }
            }
            $null = Invoke-CARestMethod -Method POST -Path 'WebServices/PIMServices.svc/Applications' -Body $body
            $script:State.ApplicationCreated = $true

            $app = [uri]::EscapeDataString([string]$script:State.ApplicationId)
            $createdApplication = Invoke-CARestMethod -Method GET -Path "WebServices/PIMServices.svc/Applications/$app/"
            # The classic endpoint normally wraps even one result in an application array.
            $application = @(Get-FirstPropertyValue -InputObject $createdApplication -PropertyNames @('application', 'Application'))[0]
            (Get-FirstPropertyValue -InputObject $application -PropertyNames @('AppID', 'appID')) | Should -Be $script:State.ApplicationId
        }

        It 'adds and lists an authentication method on the disposable AAM application' -Skip:(-not [bool]$TestConfig.TestAAMApplicationCrud) {
            # Loopback is a benign placeholder and does not grant the application access to any Safe.
            $app = [uri]::EscapeDataString([string]$script:State.ApplicationId)
            $body = @{
                authentication = [ordered]@{
                    AuthType  = 'machineAddress'
                    AuthValue = [string]$TestConfig.AdminApplicationMachineAddress
                }
            }
            $null = Invoke-CARestMethod -Method POST -Path "WebServices/PIMServices.svc/Applications/$app/Authentications/" -Body $body
            $script:State.ApplicationAuthenticationCreated = $true

            $response = Invoke-CARestMethod -Method GET -Path "WebServices/PIMServices.svc/Applications/$app/Authentications/"
            $authentications = @(Get-FirstPropertyValue -InputObject $response -PropertyNames @('authentication', 'Authentication'))
            $matchingAuthentication = @($authentications | Where-Object {
                (Get-FirstPropertyValue -InputObject $_ -PropertyNames @('AuthValue', 'authValue')) -eq $TestConfig.AdminApplicationMachineAddress
            })
            $matchingAuthentication.Count | Should -Be 1
            $script:State.ApplicationAuthenticationId = Get-FirstPropertyValue -InputObject $matchingAuthentication[0] -PropertyNames @('AuthID', 'authID', 'id', 'ID')
            $script:State.ApplicationAuthenticationId | Should -Not -BeNullOrEmpty
        }

        It 'deletes the disposable AAM authentication method' -Skip:(-not [bool]$TestConfig.TestAAMApplicationCrud) {
            # Delete the exact returned authentication ID to avoid affecting any other method.
            $app = [uri]::EscapeDataString([string]$script:State.ApplicationId)
            $auth = [uri]::EscapeDataString([string]$script:State.ApplicationAuthenticationId)
            $null = Invoke-CARestMethod -Method DELETE -Path "WebServices/PIMServices.svc/Applications/$app/Authentications/$auth/"
            $script:State.ApplicationAuthenticationCreated = $false

            $response = Invoke-CARestMethod -Method GET -Path "WebServices/PIMServices.svc/Applications/$app/Authentications/"
            ($response | ConvertTo-Json -Depth 20) | Should -Not -Match ([regex]::Escape([string]$script:State.ApplicationAuthenticationId))
        }

        It 'deletes the disposable AAM application and verifies it is gone' -Skip:(-not [bool]$TestConfig.TestAAMApplicationCrud) {
            # Application deletion completes the classic API lifecycle without any Safe authorisation changes.
            $app = [uri]::EscapeDataString([string]$script:State.ApplicationId)
            $applicationPath = "WebServices/PIMServices.svc/Applications/$app/"
            $null = Invoke-CARestMethod -Method DELETE -Path $applicationPath
            $script:State.ApplicationCreated = $false

            Test-DeletedRoute -Path $applicationPath | Should -Be $TestConfig.ExpectedMissingStatus
        }
    }
}
