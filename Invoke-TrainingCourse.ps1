<#
.SYNOPSIS
    Runs the PowerShell training course in order with local sample data.
.DESCRIPTION
    Executes each runnable training script with synthetic local inputs only. Helper files that define classes or
    settings are parsed separately because they are loaded by entry scripts rather than run as lessons.
#>
[CmdletBinding()]
param(
    [switch] $ContinueOnFailure,
    [switch] $IncludeLiveRisk
)

$Script:Root = $PSScriptRoot

<#
.SYNOPSIS
    Builds the ordered list of runnable course scripts and the sample arguments each one needs.
#>
function Get-TrainingCourseStep {
    [CmdletBinding()]
    param()

    $Steps = @(
        '01-Language-Fundamentals/ArrayIndexing.ps1',
        '01-Language-Fundamentals/ArraySlicing.ps1',
        '01-Language-Fundamentals/BreakContinue.ps1',
        '01-Language-Fundamentals/ClassesBasics.ps1',
        '01-Language-Fundamentals/ComparisonOperators.ps1',
        '01-Language-Fundamentals/ContainsVsIn.ps1',
        '01-Language-Fundamentals/DateArithmetic.ps1',
        '01-Language-Fundamentals/DoUntilLoop.ps1',
        '01-Language-Fundamentals/EnumDefinition.ps1',
        '01-Language-Fundamentals/ForLoop.ps1',
        '01-Language-Fundamentals/HereStrings.ps1',
        '01-Language-Fundamentals/JobsThreadJob.ps1',
        '01-Language-Fundamentals/MethodInvocation.ps1',
        '01-Language-Fundamentals/NullCoalescing.ps1',
        '01-Language-Fundamentals/ParallelForEach.ps1',
        '01-Language-Fundamentals/RegexMatching.ps1',
        '01-Language-Fundamentals/RequiresVersion.ps1',
        '01-Language-Fundamentals/ScriptScope.ps1',
        '01-Language-Fundamentals/StrictMode.ps1',
        '01-Language-Fundamentals/StringInterpolation.ps1',
        '01-Language-Fundamentals/SwitchStatement.ps1',
        '01-Language-Fundamentals/TernaryOperator.ps1',
        '01-Language-Fundamentals/TypeAccelerators.ps1',
        '01-Language-Fundamentals/TypeCasting.ps1',
        '02-Objects-And-Data/CalculatedProperties.ps1',
        '02-Objects-And-Data/CsvImportExport.ps1',
        '02-Objects-And-Data/Display-PSDStructure.ps1',
        '02-Objects-And-Data/DynamicMemberAccess.ps1',
        '02-Objects-And-Data/FormatDataVsObjects.ps1',
        '02-Objects-And-Data/HashtableBasics.ps1',
        '02-Objects-And-Data/JsonConversion.ps1',
        '02-Objects-And-Data/ObjectMembers.ps1',
        '02-Objects-And-Data/OrderedHashtable.ps1',
        '02-Objects-And-Data/PsCustomObject.ps1',
        '02-Objects-And-Data/SelectExpandProperty.ps1',
        '02-Objects-And-Data/SortingGrouping.ps1',
        '02-Objects-And-Data/XmlParsing.ps1',
        '03-Pipeline-And-Functions/BeginProcessEnd.ps1',
        '03-Pipeline-And-Functions/CommandDiscovery.ps1',
        '03-Pipeline-And-Functions/CommentBasedHelp.ps1',
        '03-Pipeline-And-Functions/DefaultParameterValues.ps1',
        '03-Pipeline-And-Functions/ErrorHandling.ps1',
        '03-Pipeline-And-Functions/ForEachObjectPipeline.ps1',
        '03-Pipeline-And-Functions/FunctionOutput.ps1',
        '03-Pipeline-And-Functions/InformationStream.ps1',
        '03-Pipeline-And-Functions/ParameterSplatting.ps1',
        '03-Pipeline-And-Functions/ParameterValidation.ps1',
        '03-Pipeline-And-Functions/PipelineFiltering.ps1',
        '03-Pipeline-And-Functions/PipelineInputFunction.ps1',
        '03-Pipeline-And-Functions/PreferenceVariables.ps1',
        '03-Pipeline-And-Functions/WhatIfSupport.ps1',
        '04-Files-Environment-And-Runtime/Diagnostic.ps1',
        '04-Files-Environment-And-Runtime/EnvironmentVariables.ps1',
        '04-Files-Environment-And-Runtime/FileContent.ps1',
        '04-Files-Environment-And-Runtime/FileDiscovery.ps1',
        '04-Files-Environment-And-Runtime/JoinPath.ps1',
        '04-Files-Environment-And-Runtime/NativeCommandExitCode.ps1',
        '04-Files-Environment-And-Runtime/ProcessInspection.ps1',
        '04-Files-Environment-And-Runtime/ProvidersAndDrives.ps1',
        '04-Files-Environment-And-Runtime/RestApiRequest.ps1',
        '04-Files-Environment-And-Runtime/SecureString.ps1',
        '05-Modules-And-Configuration/Caller.ps1',
        '05-Modules-And-Configuration/Check.ps1',
        '05-Modules-And-Configuration/Configure.ps1',
        '05-Modules-And-Configuration/ModuleImport.ps1',
        '05-Modules-And-Configuration/Set-Conf-User.ps1',
        '05-Modules-And-Configuration/Set-Conf.ps1',
        '05-Modules-And-Configuration/Test-PowershellDataFile.ps1',
        '06-Deployment-And-Git-Training/Deploy-GitRepository.ps1',
        '06-Deployment-And-Git-Training/Invoke-Deployment.ps1',
        '06-Deployment-And-Git-Training/Prepare-Deployment.ps1',
        '06-Deployment-And-Git-Training/Setup-GitRepoKeys.ps1',
        '06-Deployment-And-Git-Training/Test-DeployKey.ps1',
        '07-Operations-And-Directory-Services/ADAccountsMonitor.ps1',
        '07-Operations-And-Directory-Services/AddGroup-Member.ps1',
        '07-Operations-And-Directory-Services/Check-User-CLI.ps1',
        '07-Operations-And-Directory-Services/Check-User-GUI.ps1',
        '07-Operations-And-Directory-Services/CheckADAccount.ps1',
        '07-Operations-And-Directory-Services/LDAP-Win-Query.ps1',
        '07-Operations-And-Directory-Services/Scan-ADComputerOU.ps1',
        '08-Backup-And-Compatibility/Add-DataCreateLargeSafe.ps1',
        '08-Backup-And-Compatibility/AutosysRunfile.ps1',
        '08-Backup-And-Compatibility/Daily-Backup.ps1',
        '08-Backup-And-Compatibility/Extract-AutoDetectionXML.ps1',
        '08-Backup-And-Compatibility/Get-SafeInventory.ps1',
        '08-Backup-And-Compatibility/Install-VSCodePackages.ps1',
        '08-Backup-And-Compatibility/Invoke-AirgapSafeRestore.ps1',
        '08-Backup-And-Compatibility/PAS-CreateObjectList.ps1',
        '08-Backup-And-Compatibility/PAS-ProcessFailedObjects.ps1',
        '08-Backup-And-Compatibility/Save-VSCodePackages.ps1',
        '08-Backup-And-Compatibility/Test-PS51ToPS763Compatibility.ps1',
        '08-Backup-And-Compatibility/Test-Restore.ps1',
        '08-Backup-And-Compatibility/Verify-RestoredSafes.ps1',
        '08-Backup-And-Compatibility/Weekly-Backup.ps1',
        '10-Credential-Management/Certificate-Credential.ps1',
        '10-Credential-Management/Clixml-Dpapi-Credential.ps1',
        '10-Credential-Management/Credential-Decision-Matrix.ps1',
        '10-Credential-Management/EnvironmentVariable-Secret.ps1',
        '10-Credential-Management/PSCredential-Basics.ps1',
        '10-Credential-Management/PlainText-Risk.ps1',
        '10-Credential-Management/SecretManagement-Pattern.ps1',
        '10-Credential-Management/SecureString-Basics.ps1',
        '10-Credential-Management/StartProcess-Credential-Forms.ps1',
        '10-Credential-Management/Test-CredentialSampleSet.ps1',
        '10-Credential-Management/Token-Handling.ps1',
        '10-Credential-Management/WinRM-Credential-Boundary.ps1',
        '10-Credential-Management/Windows-CredentialManager-Pattern.ps1',
        '11-Deployment-Tool/Invoke-DeploymentTool.ps1',
        '11-Deployment-Tool/Test-DeploymentTool.ps1',
        '14-Deployment -Repo-Using-Git/Invoke-RepoRefresh.ps1',
        '14-Deployment -Repo-Using-Git/Run-Pull-Repo.ps1',
        '14-Deployment -Repo-Using-Git/Configure-Deployment.ps1',
        '14-Deployment -Repo-Using-Git/Tests/Test-DeploymentTool.ps1',
        '15-Testing-And-Validation/Invoke-ValidationLesson.ps1',
        '16-Logging-And-Diagnostics/Invoke-LoggingLesson.ps1',
        '17-Remoting-And-Scheduled-Execution/Invoke-ExecutionPlanLesson.ps1',
        '18-Module-Packaging/Invoke-ModulePackagingLesson.ps1',
        '19-Script-Signing-And-Security/Invoke-SigningSecurityLesson.ps1',
        '20-Rest-And-Http-Resilience/Invoke-RestResilienceLesson.ps1',
        '21-Parallel-And-CrossPlatform/Invoke-ParallelCrossPlatformLesson.ps1',
        '22-Error-Taxonomy/Invoke-ErrorTaxonomyLesson.ps1',
        '23-Argument-Completers/Invoke-ArgumentCompleterLesson.ps1',
        '24-Security-Hardening/Invoke-SecurityHardeningLesson.ps1',
        '25-Troubleshooting/Invoke-TroubleshootingLesson.ps1',
        '26-Capstone-Assessment/Invoke-CapstoneAssessment.ps1',
        '27-Upgrading-WindowsPowerShell-51-To-PowerShell-76/Invoke-UpgradeReadinessLesson.ps1'
    )

    foreach ($Step in $Steps) {
        $LiveRiskSteps = @(
            '10-Credential-Management/StartProcess-Credential-Forms.ps1'
        )

        [pscustomobject]@{
            RelativePath = $Step
            Arguments = @()
            LiveRisk = $Step -in $LiveRiskSteps
        }
    }
}

<#
.SYNOPSIS
    Parses helper scripts that are loaded by the runnable course steps.
#>
function Test-TrainingHelperScript {
    [CmdletBinding()]
    param()

    $HelperPaths = @(
        '14-Deployment -Repo-Using-Git/DeploymentSettings.ps1',
        '14-Deployment -Repo-Using-Git/Classes/DeploymentConfigurator.ps1',
        '14-Deployment -Repo-Using-Git/Classes/DeploymentModels.ps1',
        '14-Deployment -Repo-Using-Git/Classes/RepoRefreshEngine.ps1'
    )

    foreach ($HelperPath in $HelperPaths) {
        $FullPath = Join-Path -Path $Script:Root -ChildPath $HelperPath
        $Tokens = $null
        $Errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($FullPath, [ref] $Tokens, [ref] $Errors) | Out-Null
        [pscustomobject]@{
            Step = $HelperPath
            Kind = 'HelperParse'
            ExitCode = if ($Errors.Count -eq 0) { 0 } else { 1 }
        }
    }
}

<#
.SYNOPSIS
    Runs one course step in a child PowerShell process so script exits do not stop the runner.
#>
function Test-TrainingCourseStepParse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Step
    )

    $ScriptPath = Join-Path -Path $Script:Root -ChildPath $Step.RelativePath
    $Tokens = $null
    $Errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref] $Tokens, [ref] $Errors) | Out-Null
    [pscustomobject]@{
        Step = $Step.RelativePath
        Kind = 'SkippedLiveRiskParse'
        ExitCode = if ($Errors.Count -eq 0) { 0 } else { 1 }
        Output = 'Parsed only. Pass IncludeLiveRisk after explicit approval to execute this step.'
    }
}

<#
.SYNOPSIS
    Runs one course step in a child PowerShell process so script exits do not stop the runner.
#>
function Invoke-TrainingCourseStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject] $Step
    )

    $ScriptPath = Join-Path -Path $Script:Root -ChildPath $Step.RelativePath
    $Output = & pwsh -NoProfile -NonInteractive -File $ScriptPath @($Step.Arguments) 2>&1
    [pscustomobject]@{
        Step = $Step.RelativePath
        Kind = 'Run'
        ExitCode = $LASTEXITCODE
        Output = ($Output | Select-Object -First 3) -join ' '
    }
}

try {
    $Results = [System.Collections.Generic.List[object]]::new()
    foreach ($HelperResult in Test-TrainingHelperScript) {
        $Results.Add($HelperResult)
    }

    foreach ($Step in Get-TrainingCourseStep) {
        if ($Step.LiveRisk -and -not $IncludeLiveRisk.IsPresent) {
            $Result = Test-TrainingCourseStepParse -Step $Step
        } else {
            $Result = Invoke-TrainingCourseStep -Step $Step
        }
        $Results.Add($Result)
        if ($Result.ExitCode -ne 0 -and -not $ContinueOnFailure.IsPresent) {
            break
        }
    }

    $Failures = @($Results | Where-Object { $_.ExitCode -ne 0 })
    $Summary = [pscustomobject]@{
        TotalSteps = $Results.Count
        FailedSteps = $Failures.Count
        Result = if ($Failures.Count -eq 0) { 'Passed' } else { 'Failed' }
    }

    $Summary
    if ($Failures.Count -gt 0) {
        $Failures | Select-Object -Property Step, Kind, ExitCode, Output
        exit 1
    }

    exit 0
} catch {
    Write-Error -Message "Training course runner failed: $($_.Exception.Message)"
    exit 1
}
