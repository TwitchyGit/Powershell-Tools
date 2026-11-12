<#
.SYNOPSIS
    Tests configuration files on each component server against rules in the settings.

.DESCRIPTION
    Rules are in ConfigRules in the settings file. Each rule belongs to one role.
    Rule types: Exists, Contains, NotContains, KeyEquals and XmlValue.
    The rules run on the target server. File content does not travel over the network.
    A rule with Sensitive set to $true keeps the real value out of the report.

    This check only reads data. Simulation only stops the report files.

.PARAMETER Role
    Roles to test. Default is all Windows roles that have rules.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER Simulate
    Makes no changes. No report files are written.

.EXAMPLE
    .\Check-ConfigFiles.ps1 -Role CPM -Verbose
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

$ctx = Start-Check -Name 'ConfigFiles' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$probe = {
    param([object[]]$Rules)

    foreach ($rule in $Rules) {
        $outcome = [pscustomobject]@{ Id = $rule.Id; Passed = $false; Detail = '' }
        try {
            $exists = Test-Path -LiteralPath $rule.Path -PathType Leaf
            if ($rule.Type -eq 'Exists') {
                $outcome.Passed = $exists
                if ($exists) { $outcome.Detail = 'File exists.' } else { $outcome.Detail = 'File is missing.' }
            } elseif (-not $exists) {
                $outcome.Detail = 'File is missing.'
            } else {
                switch ($rule.Type) {
                    'Contains' {
                        $text = Get-Content -LiteralPath $rule.Path -Raw -ErrorAction Stop
                        $outcome.Passed = [regex]::IsMatch($text, [string]$rule.Pattern, 'IgnoreCase, Multiline')
                        if ($outcome.Passed) { $outcome.Detail = 'Pattern found.' } else { $outcome.Detail = 'Pattern not found.' }
                    }
                    'NotContains' {
                        $text = Get-Content -LiteralPath $rule.Path -Raw -ErrorAction Stop
                        $outcome.Passed = -not [regex]::IsMatch($text, [string]$rule.Pattern, 'IgnoreCase, Multiline')
                        if ($outcome.Passed) { $outcome.Detail = 'Pattern absent.' } else { $outcome.Detail = 'Pattern found. It must be absent.' }
                    }
                    'KeyEquals' {
                        $actual = $null
                        foreach ($line in (Get-Content -LiteralPath $rule.Path -ErrorAction Stop)) {
                            $trimmed = ([string]$line).Trim()
                            if ($trimmed -eq '' -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) { continue }
                            $at = $trimmed.IndexOf('=')
                            if ($at -lt 1) { continue }
                            if ($trimmed.Substring(0, $at).Trim() -ieq [string]$rule.Key) {
                                $actual = $trimmed.Substring($at + 1).Trim().Trim('"')
                                break
                            }
                        }
                        if ($null -eq $actual) {
                            $outcome.Detail = 'Key not found.'
                        } elseif ($actual -ieq [string]$rule.Value) {
                            $outcome.Passed = $true
                            $outcome.Detail = 'Key has the expected value.'
                        } elseif ($rule.Sensitive) {
                            $outcome.Detail = 'Key value differs. Value hidden.'
                        } else {
                            $outcome.Detail = "Key value is '$actual'. Expected '$($rule.Value)'."
                        }
                    }
                    'XmlValue' {
                        $xml = New-Object System.Xml.XmlDocument
                        $xml.Load($rule.Path)
                        $node = $xml.SelectSingleNode([string]$rule.XPath)
                        if ($null -eq $node) {
                            $outcome.Detail = 'XPath returned no node.'
                        } else {
                            if ($node -is [System.Xml.XmlAttribute]) { $actual = $node.Value } else { $actual = $node.InnerText }
                            if ($actual -ieq [string]$rule.Value) {
                                $outcome.Passed = $true
                                $outcome.Detail = 'Node has the expected value.'
                            } elseif ($rule.Sensitive) {
                                $outcome.Detail = 'Node value differs. Value hidden.'
                            } else {
                                $outcome.Detail = "Node value is '$actual'. Expected '$($rule.Value)'."
                            }
                        }
                    }
                    default { $outcome.Detail = "Unknown rule type '$($rule.Type)'." }
                }
            }
        } catch {
            $outcome.Detail = 'Rule error: ' + $_.Exception.Message
        }
        $outcome
    }
}

try {
    $allRules = @((Get-CheckSettings).ConfigRules)
    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Testing {0} rule(s) on {1} server(s)." -f $allRules.Count, $targets.Count)

    foreach ($t in $targets) {
        $ruleList = @()
        for ($i = 0; $i -lt $allRules.Count; $i++) {
            if ($allRules[$i].Role -ne $t.Role) { continue }
            $copy = @{}
            foreach ($key in $allRules[$i].Keys) { $copy[$key] = $allRules[$i][$key] }
            $copy['Id'] = $i
            $ruleList += $copy
        }
        if ($ruleList.Count -eq 0) {
            Write-CheckLog -Level Verbose -Message ("No rules for role {0}. Skipped {1}." -f $t.Role, $t.Host)
            continue
        }

        try {
            $outcomes = @(Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $probe -ArgumentList @(, [object[]]$ruleList) -Credential $RemoteCredential)
        } catch {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'Rule run' -Status Error -Message $_.Exception.Message
            continue
        }

        foreach ($outcome in $outcomes) {
            $rule = $allRules[[int]$outcome.Id]
            $label = [string]$rule.Description
            if (-not $label) { $label = '{0}: {1}' -f $rule.Type, (Split-Path -Leaf $rule.Path) }
            if ($outcome.Passed) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $label -Status Pass -Message $outcome.Detail
            } else {
                Add-Finding -Role $t.Role -Target $t.Host -Item $label -Status Fail -Message ('{0} ({1})' -f $outcome.Detail, $rule.Path)
            }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
