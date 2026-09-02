$CybLegacyConfigurationModulePath = 'C:\Scripts\Config\Configuration.psm1'
$CybADConfigurationModuleName = 'Configuration.psm1'
$CybSafeScanLogPath = 'D:\Logs\Scan-AllObjectsInSafes.log'

$CybPVWAEndpointSuffixes = @{
    Authentication = 'API/auth/Cyberark/Logon/'
    Accounts       = 'API/Accounts/'
    Users          = 'API/Users?ExtendedDetails=true'
    Safes          = 'API/Safes/'
}

$CybUserInformationExcludedGroupPatterns = @(
    'PVWAUser1'
    'DR*'
    'VaultUser1'
    'Member*'
)

$CybUserGroupAssignmentConfig = @{
    SafeFeedPath = 'C:\safe_feed.csv'
    UserFeedPath = 'C:\users.txt'
    OutputPath   = 'C:\output_feed.csv'
}

$CybHumanUserScanConfig = @{
    Domains = @(
        'domain1.corp.local'
        'domain2.corp.local'
        'domain3.corp.local'
    )
    ExcludePatterns = @(
        '^adm-'
        '^svc-'
        '^svc_'
        '^sa-'
        '^sa_'
        '^test'
        '\$'
    )
    OutputDirectory = 'C:\Temp'
}

$CybOnboardingRuntime = @{
    AuthTrimmed             = $null
    AccountsResult          = 0
    Header                  = $null
    LoginSplat              = @{}
    ExcludedGroupPatterns   = @($CybUserInformationExcludedGroupPatterns)
    ConfAccountCredFile     = $null
    ConnectionTimeoutSeconds = 300
    PVWALogonUrl            = $null
    PVWAGetSafesUrl         = $null
    PVWAGetUsersUrl         = $null
    PVWAAccountsUrl         = $null
    ConfDirLogs             = $null
    ConfPVWAURL             = $null
    isAutosys               = $false
    PVWAAuthBody            = $null
}

Export-ModuleMember -Variable @(
    'CybLegacyConfigurationModulePath'
    'CybADConfigurationModuleName'
    'CybSafeScanLogPath'
    'CybPVWAEndpointSuffixes'
    'CybUserInformationExcludedGroupPatterns'
    'CybUserGroupAssignmentConfig'
    'CybHumanUserScanConfig'
    'CybOnboardingRuntime'
)
