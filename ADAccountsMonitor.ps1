param(
    [string]$CfgPath = '.\monitor_accounts.cfg'
)

Import-Module ActiveDirectory -ErrorAction Stop
Import-Module .\ADAccountsMonitor.psm1 -ErrorAction Stop

function Get-EnvFromCfg {
    param(
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Output "WARN: cfg file '$Path' not found, defaulting to DEV"
        return 'DEV'
    }

    $lines = Get-Content -LiteralPath $Path | Where-Object {$_ -and $_ -notmatch '^\s*#'}
    foreach ($line in $lines) {
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2 -and $parts[0].Trim() -ieq 'Environment') {
            return $parts[1].Trim()
        }
    }

    Write-Output "WARN: Environment not found in cfg, defaulting to DEV"
    return 'DEV'
}

function Test-AccountHealth {
    param(
        [string]$DomainDns,
        [string]$AccountString
    )

    # AccountString is DOMAIN\SamAccountName
    $split = $AccountString -split '\\', 2
    if ($split.Count -ne 2) {
        return [pscustomobject]@{
            Environment      = $script:CurrentEnvironment
            Domain           = $DomainDns
            NetbiosDomain    = $null
            SamAccountName   = $AccountString
            Status           = 'Error'
            Reason           = 'Account string not in DOMAIN\Sam format'
        }
    }

    $netbios = $split[0]
    $sam     = $split[1]

    try {
        $user = Get-ADUser -Identity $sam -Server $DomainDns -ErrorAction Stop -Properties Enabled,LockedOut,AccountExpirationDate,PasswordExpired,PasswordLastSet,UserAccountControl
    } catch {
        return [pscustomobject]@{
            Environment      = $script:CurrentEnvironment
            Domain           = $DomainDns
            NetbiosDomain    = $netbios
            SamAccountName   = $sam
            Status           = 'Error'
            Reason           = "Get-ADUser failed: $($_.Exception.Message)"
        }
    }

    $now = Get-Date
    $status = 'OK'
    $reason = ''

    if (-not $user.Enabled) {
        $status = 'NotUsable'
        $reason = 'Disabled'
    } elseif ($user.LockedOut) {
        $status = 'NotUsable'
        $reason = 'LockedOut'
    } elseif ($user.AccountExpirationDate -and ($user.AccountExpirationDate -le $now)) {
        $status = 'NotUsable'
        $reason = 'AccountExpired'
    } elseif ($user.PasswordExpired) {
        $status = 'NotUsable'
        $reason = 'PasswordExpired'
    } elseif ($user.UserAccountControl -band 0x10) {
        # 0x10 = LOCKOUT or 0x20 = PASSWD_NOTREQD etc. Adjust flags as needed
        # Example of another “I would not use this” flag
        $status = 'NotUsable'
        $reason = 'UACFlagSet'
    }

    return [pscustomobject]@{
        Environment      = $script:CurrentEnvironment
        Domain           = $DomainDns
        NetbiosDomain    = $netbios
        SamAccountName   = $sam
        Status           = $status
        Reason           = $reason
    }
}

$script:CurrentEnvironment = Get-EnvFromCfg -Path $CfgPath

if (-not $ConfAccountSets.ContainsKey($script:CurrentEnvironment)) {
    Write-Output "ERROR: Environment '$script:CurrentEnvironment' not defined in ConfigModule"
    exit 1
}

$accountsByDomain = $ConfAccountSets[$script:CurrentEnvironment]

if (-not $accountsByDomain -or $accountsByDomain.Count -eq 0) {
    Write-Output "WARN: No domains or accounts defined for env '$script:CurrentEnvironment'"
    exit 0
}

Write-Output "INFO: Starting account health check for environment '$script:CurrentEnvironment'"

$results = @()

foreach ($domain in $accountsByDomain.Keys) {
    $accountList = $accountsByDomain[$domain]
    if (-not $accountList -or $accountList.Count -eq 0) {
        Write-Output "WARN: No accounts listed for domain '$domain' in env '$script:CurrentEnvironment'"
        continue
    }

    foreach ($acct in $accountList) {
        $result = Test-AccountHealth -DomainDns $domain -AccountString $acct
        $results += $result

        # For Autosys you can either just rely on CSV or print one line per account
        Write-Output ("INFO: {0} {1}\{2} Status={3} Reason={4}" -f `
            $result.Environment, $result.NetbiosDomain, $result.SamAccountName, $result.Status, $result.Reason)
    }
}

# Optionally output a CSV for downstream tools
# $results | Export-Csv -NoTypeInformation -Path '.\AccountHealth.csv'
