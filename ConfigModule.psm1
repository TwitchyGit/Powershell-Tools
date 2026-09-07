#Requires -Version 5.1

<#
.SYNOPSIS
Defines the editable configuration for the CyberArk 14.2 REST regression suite.

.DESCRIPTION
This module is the single source of truth for environment-specific values and
test defaults. It intentionally contains no administrator credential, generated
password, authorization token or object ID because those values exist only for
one run and must remain in memory.
#>

Set-StrictMode -Version Latest

# Keep all operator-editable values together so the runner and tests cannot drift.
$CybRegressionConfig = [ordered]@{
    # Suite names make the console and XML baselines unambiguous when both packs are run.
    UserSafeSuiteName       = 'CyberArk 14.2 User/Safe Regression'
    AdminSuiteName          = 'CyberArk 14.2 Administrator Regression'

    # Keep the complete PVWA application path because every REST route is built from it.
    PVWAUrl                 = 'https://pvwa.example.com/PasswordVault'

    # CyberArk is the normal local-Vault login; LDAP is also supported for the administrator.
    AuthenticationType     = 'CyberArk'
    SupportedAuthTypes     = @('CyberArk', 'LDAP')

    # A concurrent session prevents this regression run displacing an interactive session.
    ConcurrentSession      = $true

    # A short, recognisable prefix makes every disposable object easy to identify.
    TestObjectPrefix       = 'CA142T'
    MaximumPrefixLength    = 8
    MaximumSafeNameLength  = 28

    # The generated user is deliberately a normal EPV user, not an administrator.
    UserType               = 'EPVUser'
    GeneratedUserAuthType  = 'CyberArk'
    UserLocation           = '\'
    TestPasswordLength     = 24
    MinimumPasswordLength  = 16
    InitialUserFirstName   = 'CA142'
    UpdatedUserFirstName   = 'CA142Updated'
    TestUserLastName       = 'Regression'

    # The administrator suite uses a disposable Vault group and AAM application.
    AdminGroupDescription        = 'CyberArk 14.2 administrator regression group'
    UpdatedAdminGroupNameSuffix  = 'G2'
    AdminUserFirstName           = 'CA142Admin'
    AdminGroupMemberType         = 'vault'
    AdminApplicationDescription  = 'CyberArk 14.2 administrator regression application'
    AdminApplicationLocation     = '\'
    AdminApplicationMachineAddress = '127.0.0.1'
    AdminApplicationAccessFrom   = 0
    AdminApplicationAccessTo     = 23

    # Optional inventory checks can be disabled when the component is not installed.
    TestSystemHealth              = $true
    ComponentDetailIds           = @('PVWA', 'CPM', 'SessionManagement')
    TestPSMConnectorInventory     = $true
    TestLDAPDirectoryInventory    = $false
    TestLiveSessionInventory      = $false
    TestAAMApplicationCrud        = $true

    # Safe settings are explicit so create and update behaviour can be compared after an upgrade.
    SafeDescription        = 'CyberArk 14.2 REST regression test'
    UpdatedSafeDescription = 'CyberArk 14.2 REST regression test - updated'
    SafeLocation           = '\'
    ManagingCPM            = 'PasswordManager'
    NumberOfDaysRetention  = 7
    MemberSearchIn         = 'Vault'

    # Account defaults must identify an active password platform in the target environment.
    TestPlatformId         = 'WinServerLocal'

    # The reserved .invalid domain prevents the disposable account identifying a real target.
    TestAccountAddress     = 'ca142-rest.invalid'
    UpdatedAccountAddress  = 'ca142-rest-updated.invalid'
    TestAccountUserName    = 'ca142-rest-user'
    AccountManagementReason = 'Disposable CyberArk 14.2 REST regression account'
    AccountRetrievalReason  = 'CyberArk 14.2 REST regression verification'

    # Explicit status codes make negative and deletion assertions easy to adapt if required.
    ExpectedDeniedStatus   = 403
    ExpectedMissingStatus  = 404

    # Results are retained so pre-upgrade and post-upgrade runs can be compared.
    OutputVerbosity        = 'Detailed'
    ResultsDirectory       = (Join-Path $PSScriptRoot 'TestResults')
}

# Export only the configuration object; runtime state remains private to each script invocation.
Export-ModuleMember -Variable 'CybRegressionConfig'
