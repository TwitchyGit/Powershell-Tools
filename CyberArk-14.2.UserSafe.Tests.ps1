#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.2.0' }

param(
    [Parameter(Mandatory = $true)]
    [System.Collections.IDictionary]$TestConfig,

    [Parameter(Mandatory = $true)]
    [System.Management.Automation.PSCredential]$AdminCredential
)

Describe ([string]$TestConfig.UserSafeSuiteName) -Tag 'Integration', 'CyberArk14.2', 'UserSafeRegression', 'DestructiveTestObjectsOnly' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        # One suffix ties every disposable object to this run without colliding with another run.
        $script:BaseUrl = ([string]$TestConfig.PVWAUrl).TrimEnd('/')
        $runSuffix = '{0}-{1}' -f (Get-Date -Format 'MMddHHmmss'), (Get-Random -Minimum 1000 -Maximum 9999)

        # State flags are safety controls: cleanup acts only on objects this run successfully created.
        $script:State = [ordered]@{
            Token               = $null
            EndUserToken        = $null
            UserName            = '{0}-{1}-U' -f $TestConfig.TestObjectPrefix, $runSuffix
            UserId              = $null
            UserPassword        = $null
            UserCreated         = $false
            SafeName            = '{0}-{1}-S' -f $TestConfig.TestObjectPrefix, $runSuffix
            SafeUrlId           = $null
            SafeCreated         = $false
            MemberCreated       = $false
            AccountName         = '{0}-{1}-A' -f $TestConfig.TestObjectPrefix, $runSuffix
            AccountId           = $null
            AccountSecret       = $null
            AccountCreated      = $false
        }

        if ($script:State.SafeName.Length -gt $TestConfig.MaximumSafeNameLength) {
            throw "Generated Safe name '$($script:State.SafeName)' exceeds CyberArk's $($TestConfig.MaximumSafeNameLength)-character Safe name limit."
        }

        function Get-HttpStatusCode {
            param([System.Management.Automation.ErrorRecord]$ErrorRecord)

            # Prefer our sanitised exception data, then fall back to the native web response.
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
                [switch]$NoAuthentication,

                [Parameter()]
                [AllowNull()]
                [string]$AuthorizationToken
            )

            # Centralising HTTP handling gives every test the same TLS, JSON and error behaviour.
            $relativePath = $Path.TrimStart('/')
            $request = @{
                Uri         = "$script:BaseUrl/$relativePath"
                Method      = $Method
                ContentType = 'application/json'
                ErrorAction = 'Stop'
            }

            if ($PSVersionTable.PSVersion.Major -le 5) {
                # Windows PowerShell 5.1 needs this to avoid Internet Explorer engine dependency.
                $request.UseBasicParsing = $true
            }

            if (-not $NoAuthentication) {
                # Admin is the default; end-user tests explicitly supply their separate token.
                $requestToken = $script:State.Token
                if ($PSBoundParameters.ContainsKey('AuthorizationToken')) {
                    $requestToken = $AuthorizationToken
                }

                if ([string]::IsNullOrWhiteSpace([string]$requestToken)) {
                    throw 'No CyberArk authorization token is available.'
                }

                $request.Headers = @{ Authorization = $requestToken }
            }

            if ($PSBoundParameters.ContainsKey('Body')) {
                # ConvertTo-Json receives the object directly so JSON Patch arrays remain arrays.
                $request.Body = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
            }

            # Log only the method and relative route so baselines show exactly what ran without secrets.
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

                $message = "CyberArk REST $Method /$relativePath failed"
                if ($statusCode -gt 0) {
                    $message += " with HTTP $statusCode"
                }
                if (-not [string]::IsNullOrWhiteSpace($serverMessage)) {
                    $message += ": $serverMessage"
                }

                $statusLabel = if ($statusCode -gt 0) { "HTTP $statusCode" } else { 'no HTTP status' }
                Write-Host ("       [API] FAIL {0,-6} {1} ({2}; {3} ms)" -f $Method, $displayRoute, $statusLabel, $stopwatch.ElapsedMilliseconds)

                # The replacement exception keeps useful status details without echoing auth headers.
                $sanitisedException = New-Object System.Exception($message, $_.Exception)
                $sanitisedException.Data['StatusCode'] = $statusCode
                throw $sanitisedException
            }
        }

        function Get-TokenFromLogonResponse {
            param([AllowNull()][object]$Response)

            # CyberArk versions and authentication routes return either a string or a token property.
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

        function New-TestPassword {
            param([int]$Length)

            if ($Length -lt $TestConfig.MinimumPasswordLength) {
                throw "TestPasswordLength must be at least $($TestConfig.MinimumPasswordLength)."
            }

            # The fixed prefix guarantees common complexity classes; ambiguous characters are omitted.
            $characters = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%_-+'
            $randomPart = -join (1..($Length - 4) | ForEach-Object {
                $characters[(Get-Random -Minimum 0 -Maximum $characters.Length)]
            })

            return "Aa1!$randomPart"
        }

        function New-SafeMemberPermissions {
            param([bool]$AllowAccountManagement)

            # Account CRUD is granted while Safe and membership administration stay denied.
            return [ordered]@{
                useAccounts                            = $AllowAccountManagement
                retrieveAccounts                       = $AllowAccountManagement
                listAccounts                           = $true
                addAccounts                            = $AllowAccountManagement
                updateAccountContent                   = $AllowAccountManagement
                updateAccountProperties                = $AllowAccountManagement
                initiateCPMAccountManagementOperations = $false
                specifyNextAccountContent              = $false
                renameAccounts                         = $AllowAccountManagement
                deleteAccounts                         = $AllowAccountManagement
                unlockAccounts                         = $false
                manageSafe                             = $false
                manageSafeMembers                      = $false
                backupSafe                             = $false
                viewAuditLog                           = $false
                viewSafeMembers                        = $true
                accessWithoutConfirmation              = $false
                createFolders                          = $false
                deleteFolders                          = $false
                moveAccountsAndFolders                 = $false
                requestsAuthorizationLevel1            = $false
                requestsAuthorizationLevel2            = $false
            }
        }

        function Copy-ObjectForPut {
            param(
                [Parameter(Mandatory = $true)]
                [object]$InputObject,

                [Parameter(Mandatory = $true)]
                [string[]]$PropertiesToRemove
            )

            # PUT is replacement-style, so preserve editable values and remove only read-only fields.
            $copy = $InputObject | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            foreach ($propertyName in $PropertiesToRemove) {
                $copy.PSObject.Properties.Remove($propertyName)
            }
            return $copy
        }

        function Get-ExpectedMissingStatus {
            param([Parameter(Mandatory = $true)][string]$Path)

            try {
                # A successful GET means deletion did not take effect and must fail the assertion.
                $null = Invoke-CARestMethod -Method GET -Path $Path
                return 200
            }
            catch {
                return Get-HttpStatusCode -ErrorRecord $_
            }
        }

        function Remove-TestObjects {
            # Admin cleanup is authoritative even when the lower-privileged end-user flow failed.
            if (-not [string]::IsNullOrWhiteSpace([string]$script:State.Token)) {
                if ($script:State.AccountCreated -and $null -ne $script:State.AccountId) {
                    try {
                        $account = [uri]::EscapeDataString([string]$script:State.AccountId)
                        $null = Invoke-CARestMethod -Method DELETE -Path "API/Accounts/$account"
                    }
                    catch {
                        Write-Warning "Cleanup could not remove test account '$($script:State.AccountName)': $($_.Exception.Message)"
                    }
                }

                if ($script:State.MemberCreated -and $script:State.SafeCreated) {
                    try {
                        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
                        $member = [uri]::EscapeDataString([string]$script:State.UserName)
                        $null = Invoke-CARestMethod -Method DELETE -Path "API/Safes/$safe/Members/$member/"
                    }
                    catch {
                        Write-Warning "Cleanup could not remove test Safe member '$($script:State.UserName)': $($_.Exception.Message)"
                    }
                }

                if ($script:State.SafeCreated) {
                    try {
                        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
                        $null = Invoke-CARestMethod -Method DELETE -Path "API/Safes/$safe"
                    }
                    catch {
                        Write-Warning "Cleanup could not remove test Safe '$($script:State.SafeName)': $($_.Exception.Message)"
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
    }

    AfterAll {
        # Remove data before logging off because cleanup needs the administrator token.
        Remove-TestObjects

        # The generated user has a separate session which must be closed independently.
        if (-not [string]::IsNullOrWhiteSpace([string]$script:State.EndUserToken)) {
            try {
                $null = Invoke-CARestMethod -Method POST -Path 'API/Auth/Logoff' -AuthorizationToken $script:State.EndUserToken
            }
            catch {
                Write-Warning "CyberArk end-user logoff failed: $($_.Exception.Message)"
            }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$script:State.Token)) {
            try {
                $null = Invoke-CARestMethod -Method POST -Path 'API/Auth/Logoff'
            }
            catch {
                Write-Warning "CyberArk logoff failed: $($_.Exception.Message)"
            }
        }

        $script:State.Token = $null
        $script:State.EndUserToken = $null
        $script:State.UserPassword = $null
        $script:State.AccountSecret = $null
    }

    It 'authenticates once with the supplied administrator credential' {
        # Only the administrator is requested from the operator; all other credentials are generated.
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

    It 'returns the logged-on administrator through the current-user API' {
        # This proves that the token represents the intended operator, not merely any valid session.
        $currentUser = Invoke-CARestMethod -Method GET -Path 'API/CurrentUser'

        $currentUser | Should -Not -BeNullOrEmpty
        $currentUser.username | Should -Be $AdminCredential.UserName
    }

    It 'creates a uniquely named local Vault user' {
        # Retain the random password only as a SecureString so the generated user can be tested later.
        $testPassword = New-TestPassword -Length ([int]$TestConfig.TestPasswordLength)
        $script:State.UserPassword = ConvertTo-SecureString -String $testPassword -AsPlainText -Force
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
                firstName = [string]$TestConfig.InitialUserFirstName
                lastName  = [string]$TestConfig.TestUserLastName
            }
        }

        try {
            $createdUser = Invoke-CARestMethod -Method POST -Path 'API/Users' -Body $body
            $script:State.UserCreated = $true
            $script:State.UserId = $createdUser.id
        }
        finally {
            $body.initialPassword = $null
            $testPassword = $null
        }

        $createdUser | Should -Not -BeNullOrEmpty
        $script:State.UserId | Should -Not -BeNullOrEmpty
        $createdUser.username | Should -Be $script:State.UserName
    }

    It 'reads the new user by numeric ID' {
        # Reading by immutable ID proves the create response can drive later lifecycle operations.
        $user = Invoke-CARestMethod -Method GET -Path "API/Users/$($script:State.UserId)"

        $user.id | Should -Be $script:State.UserId
        $user.username | Should -Be $script:State.UserName
        $user.enableUser | Should -BeTrue
    }

    It 'updates the new user and verifies the persisted value' {
        # Fetch first because the CyberArk user PUT replaces the editable representation.
        $user = Invoke-CARestMethod -Method GET -Path "API/Users/$($script:State.UserId)"
        $updateBody = Copy-ObjectForPut -InputObject $user -PropertiesToRemove @(
            'id',
            'lastSuccessfulLoginDate',
            'source',
            'componentUser',
            'groupsMembership',
            'authenticationMethod'
        )

        if ($null -eq $updateBody.personalDetails) {
            $updateBody | Add-Member -MemberType NoteProperty -Name personalDetails -Value ([pscustomobject]@{})
        }
        if ($null -eq $updateBody.personalDetails.PSObject.Properties['firstName']) {
            $updateBody.personalDetails | Add-Member -MemberType NoteProperty -Name firstName -Value ([string]$TestConfig.UpdatedUserFirstName)
        }
        else {
            $updateBody.personalDetails.firstName = [string]$TestConfig.UpdatedUserFirstName
        }

        $null = Invoke-CARestMethod -Method PUT -Path "API/Users/$($script:State.UserId)" -Body $updateBody
        $updatedUser = Invoke-CARestMethod -Method GET -Path "API/Users/$($script:State.UserId)"

        $updatedUser.personalDetails.firstName | Should -Be $TestConfig.UpdatedUserFirstName
    }

    It 'creates a uniquely named Safe' {
        # The Safe is an isolated container for membership and account tests in this run.
        $body = [ordered]@{
            safeName              = $script:State.SafeName
            description           = [string]$TestConfig.SafeDescription
            location              = [string]$TestConfig.SafeLocation
            OLACEnabled           = $false
            managingCPM           = [string]$TestConfig.ManagingCPM
            numberOfDaysRetention = [int]$TestConfig.NumberOfDaysRetention
        }

        $createdSafe = Invoke-CARestMethod -Method POST -Path 'API/Safes' -Body $body
        $script:State.SafeCreated = $true
        $script:State.SafeUrlId = $createdSafe.safeUrlId
        if ([string]::IsNullOrWhiteSpace([string]$script:State.SafeUrlId)) {
            $script:State.SafeUrlId = $script:State.SafeName
        }

        $createdSafe | Should -Not -BeNullOrEmpty
        $createdSafe.safeName | Should -Be $script:State.SafeName
    }

    It 'reads the new Safe by Safe URL ID' {
        # Use the returned URL ID because it is the API identifier used by later operations.
        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
        $safeDetails = Invoke-CARestMethod -Method GET -Path "API/Safes/$safe"

        $safeDetails.safeName | Should -Be $script:State.SafeName
        $safeDetails.description | Should -Be $TestConfig.SafeDescription
    }

    It 'updates the Safe and verifies the persisted description' {
        # A harmless description change proves update support without changing retention semantics.
        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
        $body = [ordered]@{
            safeName              = $script:State.SafeName
            description           = [string]$TestConfig.UpdatedSafeDescription
            location              = [string]$TestConfig.SafeLocation
            OLACEnabled           = $false
            managingCPM           = [string]$TestConfig.ManagingCPM
            numberOfDaysRetention = [int]$TestConfig.NumberOfDaysRetention
        }

        $null = Invoke-CARestMethod -Method PUT -Path "API/Safes/$safe" -Body $body
        $updatedSafe = Invoke-CARestMethod -Method GET -Path "API/Safes/$safe"

        $updatedSafe.description | Should -Be $TestConfig.UpdatedSafeDescription
    }

    It 'adds the new user as a Safe member with basic list permissions' {
        # Begin read-only so the next test proves membership permission updates take effect.
        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
        $body = [ordered]@{
            memberName = $script:State.UserName
            searchIn   = [string]$TestConfig.MemberSearchIn
            memberType = 'user'
            permissions = New-SafeMemberPermissions -AllowAccountManagement $false
        }

        $createdMember = Invoke-CARestMethod -Method POST -Path "API/Safes/$safe/Members" -Body $body
        $script:State.MemberCreated = $true

        $createdMember | Should -Not -BeNullOrEmpty
        $createdMember.memberName | Should -Be $script:State.UserName
    }

    It 'reads the new Safe member by name' {
        # Validate the initial least-privilege state before granting account CRUD permissions.
        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
        $member = [uri]::EscapeDataString([string]$script:State.UserName)
        $memberDetails = Invoke-CARestMethod -Method GET -Path "API/Safes/$safe/Members/$member/"

        $memberDetails.memberName | Should -Be $script:State.UserName
        $memberDetails.permissions.listAccounts | Should -BeTrue
        $memberDetails.permissions.useAccounts | Should -BeFalse
    }

    It 'updates the Safe member with account CRUD permissions and verifies them' {
        # Grant only account operations; Safe and membership administration deliberately remain false.
        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
        $member = [uri]::EscapeDataString([string]$script:State.UserName)
        $body = [ordered]@{
            membershipExpirationDate = $null
            permissions = New-SafeMemberPermissions -AllowAccountManagement $true
        }

        $null = Invoke-CARestMethod -Method PUT -Path "API/Safes/$safe/Members/$member/" -Body $body
        $updatedMember = Invoke-CARestMethod -Method GET -Path "API/Safes/$safe/Members/$member/"

        $updatedMember.permissions.useAccounts | Should -BeTrue
        $updatedMember.permissions.retrieveAccounts | Should -BeTrue
        $updatedMember.permissions.addAccounts | Should -BeTrue
        $updatedMember.permissions.updateAccountProperties | Should -BeTrue
        $updatedMember.permissions.deleteAccounts | Should -BeTrue
        $updatedMember.permissions.manageSafe | Should -BeFalse
        $updatedMember.permissions.manageSafeMembers | Should -BeFalse
    }

    It 'authenticates as the generated end user without another operator prompt' {
        # A second token proves subsequent account tests run with end-user rights, not admin rights.
        $endUserCredential = New-Object System.Management.Automation.PSCredential(
            $script:State.UserName,
            $script:State.UserPassword
        )
        $plainPassword = $endUserCredential.GetNetworkCredential().Password
        $logonBody = [ordered]@{
            username          = $script:State.UserName
            password          = $plainPassword
            concurrentSession = [bool]$TestConfig.ConcurrentSession
        }

        try {
            $response = Invoke-CARestMethod -Method POST -Path "API/Auth/$($TestConfig.GeneratedUserAuthType)/Logon" -Body $logonBody -NoAuthentication
            $script:State.EndUserToken = Get-TokenFromLogonResponse -Response $response
        }
        finally {
            $logonBody.password = $null
            $plainPassword = $null
            $endUserCredential = $null
        }

        $script:State.EndUserToken | Should -Not -BeNullOrEmpty
    }

    It 'creates a disposable account as the generated end user' {
        # Use a false .invalid address and disable CPM management so no real target is contacted.
        $accountSecretPlain = New-TestPassword -Length ([int]$TestConfig.TestPasswordLength)
        $script:State.AccountSecret = ConvertTo-SecureString -String $accountSecretPlain -AsPlainText -Force
        $body = [ordered]@{
            name       = $script:State.AccountName
            address    = [string]$TestConfig.TestAccountAddress
            userName   = [string]$TestConfig.TestAccountUserName
            platformId = [string]$TestConfig.TestPlatformId
            safeName   = $script:State.SafeName
            secretType = 'password'
            secret     = $accountSecretPlain
            platformAccountProperties = @{}
            secretManagement = [ordered]@{
                automaticManagementEnabled = $false
                manualManagementReason      = [string]$TestConfig.AccountManagementReason
            }
        }

        try {
            $createdAccount = Invoke-CARestMethod -Method POST -Path 'API/Accounts' -Body $body -AuthorizationToken $script:State.EndUserToken
            $script:State.AccountCreated = $true
            $script:State.AccountId = $createdAccount.id
        }
        finally {
            $body.secret = $null
            $accountSecretPlain = $null
        }

        $createdAccount | Should -Not -BeNullOrEmpty
        $script:State.AccountId | Should -Not -BeNullOrEmpty
        $createdAccount.safeName | Should -Be $script:State.SafeName
    }

    It 'lists and reads the disposable account as the generated end user' {
        # Search exercises the normal end-user discovery path before direct ID retrieval.
        $encodedSafeName = [uri]::EscapeDataString($script:State.SafeName)
        $accountList = Invoke-CARestMethod -Method GET -Path "API/Accounts?filter=safeName%20eq%20$encodedSafeName" -AuthorizationToken $script:State.EndUserToken
        $matchingAccounts = @($accountList.value | Where-Object { $_.id -eq $script:State.AccountId })

        $account = [uri]::EscapeDataString([string]$script:State.AccountId)
        $accountDetails = Invoke-CARestMethod -Method GET -Path "API/Accounts/$account" -AuthorizationToken $script:State.EndUserToken

        $matchingAccounts.Count | Should -Be 1
        $accountDetails.id | Should -Be $script:State.AccountId
        $accountDetails.userName | Should -Be $TestConfig.TestAccountUserName
    }

    It 'retrieves the disposable secret as the generated end user' {
        # Compare only in memory to prove RetrieveAccounts works without printing the secret.
        $expectedSecret = (New-Object System.Management.Automation.PSCredential('ignored', $script:State.AccountSecret)).GetNetworkCredential().Password
        $account = [uri]::EscapeDataString([string]$script:State.AccountId)
        try {
            $retrievedSecret = Invoke-CARestMethod -Method POST -Path "API/Accounts/$account/Password/Retrieve" -Body @{
                reason = [string]$TestConfig.AccountRetrievalReason
            } -AuthorizationToken $script:State.EndUserToken

            $retrievedSecret | Should -Be $expectedSecret
        }
        finally {
            $retrievedSecret = $null
            $expectedSecret = $null
        }
    }

    It 'updates the disposable account and verifies the persisted address' {
        # JSON Patch changes one benign property and leaves the stored secret untouched.
        $account = [uri]::EscapeDataString([string]$script:State.AccountId)
        $operations = @(
            [ordered]@{
                op    = 'replace'
                path  = '/address'
                value = [string]$TestConfig.UpdatedAccountAddress
            }
        )

        $null = Invoke-CARestMethod -Method PATCH -Path "API/Accounts/$account" -Body $operations -AuthorizationToken $script:State.EndUserToken
        $updatedAccount = Invoke-CARestMethod -Method GET -Path "API/Accounts/$account" -AuthorizationToken $script:State.EndUserToken

        $updatedAccount.address | Should -Be $TestConfig.UpdatedAccountAddress
    }

    It 'cannot administer the Safe with account-only end-user permissions' {
        # This negative test detects accidental privilege expansion after an upgrade or policy change.
        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
        $body = [ordered]@{
            safeName              = $script:State.SafeName
            description           = 'This update must be denied'
            location              = [string]$TestConfig.SafeLocation
            OLACEnabled           = $false
            managingCPM           = [string]$TestConfig.ManagingCPM
            numberOfDaysRetention = [int]$TestConfig.NumberOfDaysRetention
        }

        try {
            $null = Invoke-CARestMethod -Method PUT -Path "API/Safes/$safe" -Body $body -AuthorizationToken $script:State.EndUserToken
            $statusCode = 200
        }
        catch {
            $statusCode = Get-HttpStatusCode -ErrorRecord $_
        }

        $statusCode | Should -Be $TestConfig.ExpectedDeniedStatus
    }

    It 'deletes the disposable account as the generated end user and verifies it is gone' {
        # Account deletion completes end-user CRUD before membership and user cleanup begins.
        $account = [uri]::EscapeDataString([string]$script:State.AccountId)
        $accountPath = "API/Accounts/$account"
        $null = Invoke-CARestMethod -Method DELETE -Path $accountPath -AuthorizationToken $script:State.EndUserToken
        $script:State.AccountCreated = $false

        try {
            $null = Invoke-CARestMethod -Method GET -Path $accountPath -AuthorizationToken $script:State.EndUserToken
            $statusCode = 200
        }
        catch {
            $statusCode = Get-HttpStatusCode -ErrorRecord $_
        }

        $statusCode | Should -Be $TestConfig.ExpectedMissingStatus
    }

    It 'deletes the test Safe member and verifies it is gone' {
        # Remove membership before deleting its user so the membership API is independently verified.
        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
        $member = [uri]::EscapeDataString([string]$script:State.UserName)
        $null = Invoke-CARestMethod -Method DELETE -Path "API/Safes/$safe/Members/$member/"
        $script:State.MemberCreated = $false

        Get-ExpectedMissingStatus -Path "API/Safes/$safe/Members/$member/" | Should -Be $TestConfig.ExpectedMissingStatus
    }

    It 'deletes the test user and verifies it is gone' {
        # Delete only the generated user ID captured from this run's create response.
        $userPath = "API/Users/$($script:State.UserId)"
        $null = Invoke-CARestMethod -Method DELETE -Path $userPath
        $script:State.UserCreated = $false

        Get-ExpectedMissingStatus -Path $userPath | Should -Be $TestConfig.ExpectedMissingStatus
    }

    It 'deletes the test Safe and verifies it is gone' {
        # The Safe is deleted last because all account and membership tests depend on it.
        $safe = [uri]::EscapeDataString([string]$script:State.SafeUrlId)
        $safePath = "API/Safes/$safe"
        $null = Invoke-CARestMethod -Method DELETE -Path $safePath
        $script:State.SafeCreated = $false

        Get-ExpectedMissingStatus -Path $safePath | Should -Be $TestConfig.ExpectedMissingStatus
    }
}
