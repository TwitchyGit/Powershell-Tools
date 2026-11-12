<#
.SYNOPSIS
    Tests installed product versions against rules in the settings.

.DESCRIPTION
    Rules are in VersionRules in the settings file. A rule matches the product name in
    Programs and Features. Each rule can set:
      Minimum            The installed version must be at least this value.
      Exact              The installed version must equal this value.
      RequireConsistent  All servers of the role must show the same version.

    This check only reads data. Simulation only stops the report files.

.PARAMETER Role
    Roles to test. Default is all Windows roles that have rules.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER Simulate
    Makes no changes. No report files are written.

.EXAMPLE
    .\Check-ComponentVersions.ps1 -Verbose
#>
[CmdletBinding()]
param(
    [string[]]$Role,
    [string[]]$ComputerName,
    [switch]$Simulate,
    [pscredential]$RemoteCredential,
    [string]$OutputDirectory
)

if ($PSBoundParameters.ContainsKey('Debug')) { $DebugPreference = 'SilentlyContinue' }

$settingsModule = $env:ONPREM_CHECKS_SETTINGS
if ([string]::IsNullOrWhiteSpace($settingsModule)) {
    $settingsModule = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Config\CheckSettings.psm1'
}
Import-Module -Name $settingsModule -Force -ErrorAction Stop

$ctx = Start-Check -Name 'ComponentVersions' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$probe = {
    param([string[]]$Patterns)
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName } | ForEach-Object {
        $name = [string]$_.DisplayName
        foreach ($pattern in $Patterns) {
            if ($name -like $pattern) {
                [pscustomobject]@{ Pattern = $pattern; Name = $name; Version = [string]$_.DisplayVersion }
                break
            }
        }
    }
}

try {
    $rules = @((Get-CheckSettings).VersionRules)
    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Testing {0} version rule(s) on {1} server(s)." -f $rules.Count, $targets.Count)

    # Versions seen for each rule index and server. Used for the consistency test.
    $seen = @{}

    foreach ($t in $targets) {
        $roleRules = @()
        for ($i = 0; $i -lt $rules.Count; $i++) {
            if ($rules[$i].Role -eq $t.Role) { $roleRules += $i }
        }
        if ($roleRules.Count -eq 0) {
            Write-CheckLog -Level Verbose -Message ("No version rules for role {0}. Skipped {1}." -f $t.Role, $t.Host)
            continue
        }

        $patterns = [string[]]@($roleRules | ForEach-Object { $rules[$_].NamePattern })
        try {
            $installed = @(Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $probe -ArgumentList @(, $patterns) -Credential $RemoteCredential)
        } catch {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'Software query' -Status Error -Message $_.Exception.Message
            continue
        }

        foreach ($index in $roleRules) {
            $rule = $rules[$index]
            $found = @($installed | Where-Object { $_.Pattern -eq $rule.NamePattern })
            $item = [string]$rule.NamePattern

            if ($found.Count -eq 0) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Fail -Message 'Product is not installed.'
                continue
            }
            if ($found.Count -gt 1) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Warn `
                    -Message ('{0} products match this name. The first one is tested.' -f $found.Count)
            }

            $text = [string]$found[0].Version
            $version = ConvertTo-SafeVersion -Text $text
            if ($null -eq $version) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Warn -Message ("Cannot read a version from '{0}'." -f $text)
                continue
            }

            if (-not $seen.ContainsKey($index)) { $seen[$index] = @{} }
            $seen[$index][$t.Host] = $text

            $problems = @()
            if ($rule.Minimum) {
                $min = ConvertTo-SafeVersion -Text ([string]$rule.Minimum)
                if ($null -ne $min -and $version -lt $min) { $problems += ('below minimum {0}' -f $rule.Minimum) }
            }
            if ($rule.Exact) {
                $exact = ConvertTo-SafeVersion -Text ([string]$rule.Exact)
                if ($null -ne $exact -and $version -ne $exact) { $problems += ('expected exactly {0}' -f $rule.Exact) }
            }

            if ($problems.Count -gt 0) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Fail -Message ('Version {0}: {1}.' -f $text, ($problems -join '; '))
            } else {
                Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Pass -Message ('Version {0}.' -f $text)
            }
        }
    }

    foreach ($index in $seen.Keys) {
        $rule = $rules[[int]$index]
        if (-not $rule.RequireConsistent) { continue }
        $versions = @($seen[$index].Values | Select-Object -Unique)
        if ($seen[$index].Count -ge 2 -and $versions.Count -gt 1) {
            $detail = ($seen[$index].GetEnumerator() | Sort-Object -Property Name | ForEach-Object { '{0}={1}' -f $_.Name, $_.Value }) -join ', '
            Add-Finding -Role $rule.Role -Target 'All servers' -Item ('Consistency: ' + $rule.NamePattern) -Status Fail -Message ('Versions differ. ' + $detail)
        } elseif ($seen[$index].Count -ge 2) {
            Add-Finding -Role $rule.Role -Target 'All servers' -Item ('Consistency: ' + $rule.NamePattern) -Status Pass -Message 'All servers show the same version.'
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
