
outputs/Test-PS51ToPS763Compatibility.ps1
}}, Category, File, Line, Item)

$blockerCount = @($findings | Where-Object { $_.Severity -eq 'BLOCKER' }).Count
$warningCount = @($findings | Where-Object { $_.Severity -eq 'WARNING' }).Count
$reviewCount = @($findings | Where-Object { $_.Severity -eq 'REVIEW' }).Count
$infoCount = @($findings | Where-Object { $_.Severity -eq 'INFO' }).Count

$conclusion = if ($blockerCount -gt 0) {
    'The supplied script is **not cleared for PowerShell 7.6.3**. Resolve the blocking findings, then repeat the audit and controlled runtime testing.'
}
else {
    'No statically confirmed blocker was found. This is **not a guarantee of runtime compatibility**; complete the listed manual checks and a controlled PowerShell 7.6.3 test.'
}

$moduleComparison = @()
$allModuleNames = @($ps51ModuleNames + $ps7ModuleNames | Sort-Object -Unique)
foreach ($moduleName in $allModuleNames) {
    $sourceModule = Get-HighestModule -Modules @($ps51.AvailableModules) -Name $moduleName
    $targetModule = Get-HighestModule -Modules @($ps7.AvailableModules) -Name $moduleName
    $moduleComparison += [pscustomobject][ordered]@{
        Name                    = $moduleName
        PS51HighestVersion      = $(if ($sourceModule) { $sourceModule.Version } else { '' })
        PS51Path                = $(if ($sourceModule) { $sourceModule.Path } else { '' })
        PS7HighestVersion       = $(if ($targetModule) { $targetModule.Version } else { '' })
        PS7Path                 = $(if ($targetModule) { $targetModule.Path } else { '' })
        PS7CompatiblePSEditions = $(if ($targetModule) { ConvertTo-DisplayText $targetModule.CompatiblePSEditions } else { '' })
        OnlyIn                 = $(
            if ($sourceModule -and -not $targetModule) { 'Windows PowerShell 5.1' }
            elseif ($targetModule -and -not $sourceModule) { 'PowerShell 7' }
            else { '' }
        )
    }
}

$report = [pscustomobject][ordered]@{
    SchemaVersion          = '1.0'
    GeneratedAt            = (Get-Date).ToString('o')
    ScriptPath             = $resolvedScriptPath
    RequestedTargetVersion = [string]$TargetPowerShellVersion
    IncludeProfileSessions = [bool]$IncludeProfileSessions
    Summary                = [pscustomobject][ordered]@{
        Blockers    = $blockerCount
        Warnings    = $warningCount
        Review      = $reviewCount
        Information = $infoCount
        Conclusion  = $conclusion
    }
    WindowsPowerShell      = [pscustomobject][ordered]@{
        Version                  = $ps51.Version
        Edition                  = $ps51.Edition
        Executable               = $ps51.Executable
        Identity                 = $ps51.Identity
        Sid                      = $ps51.Sid
        Bitness                  = $(if ([bool]$ps51.Is64BitProcess) { '64-bit' } else { '32-bit' })
        LanguageMode             = $ps51.LanguageMode
        Culture                  = ("{0}/{1}" -f $ps51.Culture, $ps51.UICulture)
        PSHome                   = $ps51.PSHome
        ModulePathEntries        = @($ps51.ModulePathEntries)
        Profiles                 = @($ps51.Profiles)
        ExecutionPolicies        = @($ps51.ExecutionPolicies)
        AvailableModuleNameCount = $ps51ModuleNames.Count
    }
    PowerShell7            = [pscustomobject][ordered]@{
        Version                  = $ps7.Version
        Edition                  = $ps7.Edition
        Executable               = $ps7.Executable
        Identity                 = $ps7.Identity
        Sid                      = $ps7.Sid
        Bitness                  = $(if ([bool]$ps7.Is64BitProcess) { '64-bit' } else { '32-bit' })
        LanguageMode             = $ps7.LanguageMode
        Culture                  = ("{0}/{1}" -f $ps7.Culture, $ps7.UICulture)
        PSHome                   = $ps7.PSHome
        ModulePathEntries        = @($ps7.ModulePathEntries)
        Profiles                 = @($ps7.Profiles)
        ExecutionPolicies        = @($ps7.ExecutionPolicies)
        AvailableModuleNameCount = $ps7ModuleNames.Count
    }
    ParsedFiles             = @($ps51.ParsedFiles)
    Findings                = @($findings)
    ModuleComparison        = @($moduleComparison)
    RawEvidence             = [pscustomobject][ordered]@{
        WindowsPowerShellClean = $ps51
        PowerShell7Clean       = $ps7
        WindowsPowerShellProfile = $ps51Profile
        PowerShell7Profile       = $ps7Profile
    }
}

$markdownPath = Join-Path $OutputDirectory 'compatibility-report.md'
$jsonPath = Join-Path $OutputDirectory 'compatibility-audit.json'
$findingsCsvPath = Join-Path $OutputDirectory 'compatibility-findings.csv'
$modulesCsvPath = Join-Path $OutputDirectory 'module-comparison.csv'

$report | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$findings | Export-Csv -LiteralPath $findingsCsvPath -NoTypeInformation -Encoding UTF8
$moduleComparison | Export-Csv -LiteralPath $modulesCsvPath -NoTypeInformation -Encoding UTF8
Write-MarkdownReport -Path $markdownPath -Report $report

Remove-Item -LiteralPath $ps51ResultPath, $ps7ResultPath, $ps51ProfileResultPath, $ps7ProfileResultPath `
    -Force -ErrorAction SilentlyContinue

Write-Output ("Compatibility audit complete: {0}" -f $markdownPath)
Write-Output ("Blocking findings: {0}; warnings: {1}; manual review: {2}; information: {3}" -f
    $blockerCount, $warningCount, $reviewCount, $infoCount)

if ($blockerCount -gt 0) {
    exit 1
}
exit 0
