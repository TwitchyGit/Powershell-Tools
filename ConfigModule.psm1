<#
.SYNOPSIS
    Provides shared configuration for the CyberArk user-onboarding scripts.
.DESCRIPTION
    Defines module paths, PVWA endpoint suffixes, report locations, group filters,
    feed paths, Active Directory scan settings and shared onboarding runtime state.
#>

# Keep machine-specific module locations in one authoritative configuration.
$CybLegacyConfigurationModulePath = 'C:\Scripts\Config\Configuration.psm1'
$CybADConfigurationModuleName = 'Configuration.psm1'
$CybSafeScanLogPath = 'D:\Logs\Scan-AllObjectsInSafes.log'

# Store suffixes separately so callers can apply one normalized PVWA base URL.
$CybPVWAEndpointSuffixes = @{
    Authentication = 'API/auth/Cyberark/Logon/'
    Accounts       = 'API/Accounts/'
    Users          = 'API/Users?ExtendedDetails=true'
    Safes          = 'API/Safes/'
}

# Hide internal and system groups from human-user membership results.
$CybUserInformationExcludedGroupPatterns = @(
    'PVWAUser1'
    'DR*'
    'VaultUser1'
    'Member*'
)

# Keep assignment feed locations consistent across onboarding scripts.
$CybUserGroupAssignmentConfig = @{
    SafeFeedPath = 'C:\safe_feed.csv'
    UserFeedPath = 'C:\users.txt'
    OutputPath   = 'C:\output_feed.csv'
}

# Exclude service-style names before the more expensive human-user processing.
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

# Keep mutable API state inside the importing function module.
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

# Export only values consumed by active launchers and modules.
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
