using namespace System.Collections.Generic

class DeploymentMessage {
    [string]$EnvironmentName
    [string]$HostName
    [string]$ToolName
    [string]$StageName
    [string]$Level
    [string]$Message
    [datetime]$CreatedAt

    DeploymentMessage(
        [string]$EnvironmentName,
        [string]$HostName,
        [string]$ToolName,
        [string]$StageName,
        [string]$Level,
        [string]$Message
    ) {
        $this.EnvironmentName = $EnvironmentName
        $this.HostName = $HostName
        $this.ToolName = $ToolName
        $this.StageName = $StageName
        $this.Level = $Level
        $this.Message = $Message
        $this.CreatedAt = [datetime]::UtcNow
    }

    [pscustomobject] ToObject() {
        return [pscustomobject]@{
            CreatedAt = $this.CreatedAt.ToString('o')
            Level = $this.Level
            Environment = $this.EnvironmentName
            Host = $this.HostName
            Tool = $this.ToolName
            Stage = $this.StageName
            Message = $this.Message
        }
    }
}

class DeploymentReport {
    [List[DeploymentMessage]]$Messages
    [List[object]]$Decisions
    [List[object]]$StageResults
    [bool]$Passed

    DeploymentReport() {
        $this.Messages = [List[DeploymentMessage]]::new()
        $this.Decisions = [List[object]]::new()
        $this.StageResults = [List[object]]::new()
        $this.Passed = $true
    }

    [void] AddMessage(
        [string]$EnvironmentName,
        [string]$HostName,
        [string]$ToolName,
        [string]$StageName,
        [string]$Level,
        [string]$Message
    ) {
        $this.Messages.Add([DeploymentMessage]::new(
            $EnvironmentName,
            $HostName,
            $ToolName,
            $StageName,
            $Level,
            $Message
        ))

        if ($Level -eq 'Error') {
            $this.Passed = $false
        }
    }

    [pscustomobject] ToObject() {
        return [pscustomobject]@{
            Passed = $this.Passed
            Messages = @($this.Messages | ForEach-Object { $_.ToObject() })
            Decisions = @($this.Decisions)
            StageResults = @($this.StageResults)
        }
    }
}

class DeploymentConfigValidator {
    [pscustomobject]$Config

    DeploymentConfigValidator([pscustomobject]$Config) {
        $this.Config = $Config
    }

    [object[]] Test() {
        $Findings = [List[object]]::new()
        $EnvironmentNames = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $DestinationKeys = [HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        if (-not $this.Config.Environments) {
            $Findings.Add($this.NewFinding('Configuration', 'Fail', 'No environments were defined.'))
        }

        foreach ($Environment in @($this.Config.Environments)) {
            if ([string]::IsNullOrWhiteSpace($Environment.Name)) {
                $Findings.Add($this.NewFinding('Configuration', 'Fail', 'An environment has no name.'))
            } else {
                [void]$EnvironmentNames.Add($Environment.Name)
            }

            if ([string]::IsNullOrWhiteSpace($Environment.LogRoot)) {
                $Findings.Add($this.NewFinding($Environment.Name, 'Fail', 'Environment has no log root.'))
            }
        }

        foreach ($Tool in @($this.Config.Tools)) {
            $this.TestTool($Tool, $EnvironmentNames, $DestinationKeys, $Findings)
        }

        if ($Findings.Count -eq 0) {
            $Findings.Add($this.NewFinding('Configuration', 'Pass', 'Configuration passed local validation.'))
        }

        return $Findings.ToArray()
    }

    hidden [void] TestTool(
        [pscustomobject]$Tool,
        [HashSet[string]]$EnvironmentNames,
        [HashSet[string]]$DestinationKeys,
        [List[object]]$Findings
    ) {
        if ([string]::IsNullOrWhiteSpace($Tool.Name)) {
            $Findings.Add($this.NewFinding('Tool', 'Fail', 'A tool has no name.'))
            return
        }

        if ($Tool.Environment -notin $EnvironmentNames) {
            $Message = 'Tool {0} references missing environment {1}.' -f $Tool.Name, $Tool.Environment
            $Findings.Add($this.NewFinding($Tool.Name, 'Fail', $Message))
        }

        foreach ($HostItem in @($Tool.Hosts)) {
            if ([string]::IsNullOrWhiteSpace($HostItem.Name)) {
                $Findings.Add($this.NewFinding($Tool.Name, 'Fail', 'Tool has a host entry with no name.'))
                continue
            }

            $Key = '{0}|{1}|{2}' -f $Tool.Environment, $HostItem.Name, $Tool.Destination
            if (-not $DestinationKeys.Add($Key)) {
                $Message = 'Destination {0} is claimed more than once on host {1}.' -f $Tool.Destination, $HostItem.Name
                $Findings.Add($this.NewFinding($Tool.Name, 'Fail', $Message))
            }
        }

        foreach ($Stage in @($Tool.Stages)) {
            if ([string]::IsNullOrWhiteSpace($Stage.Name)) {
                $Findings.Add($this.NewFinding($Tool.Name, 'Fail', 'Tool has a stage with no name.'))
            }

            if ([string]::IsNullOrWhiteSpace($Stage.Account)) {
                $Message = 'Stage {0} has no account binding.' -f $Stage.Name
                $Findings.Add($this.NewFinding($Tool.Name, 'Fail', $Message))
            }

            foreach ($Step in @($Stage.Steps)) {
                if ([string]::IsNullOrWhiteSpace($Step.Name)) {
                    $Findings.Add($this.NewFinding($Tool.Name, 'Fail', 'A step has no name.'))
                }
            }
        }
    }

    hidden [pscustomobject] NewFinding(
        [string]$Scope,
        [string]$Result,
        [string]$Message
    ) {
        return [pscustomobject]@{
            Scope = $Scope
            Result = $Result
            Message = $Message
        }
    }
}

class BranchVersionResolver {
    [pscustomobject] Resolve([pscustomobject]$Source, [switch]$Unattended) {
        $Branches = @($Source.Branches | Sort-Object -Property LastActivityUtc -Descending)
        $DefaultBranch = $Branches | Where-Object { $_.Name -eq $Source.DefaultBranch } | Select-Object -First 1
        $CurrentBranch = $Branches | Where-Object { $_.Name -eq $Source.CurrentBranch } | Select-Object -First 1
        $MostRecentBranch = $Branches | Select-Object -First 1

        if (-not $MostRecentBranch) {
            return $this.NewDecision('NoBranch', $null, 'No branches are available for this source.')
        }

        if ($CurrentBranch) {
            if ($MostRecentBranch.Name -eq $CurrentBranch.Name) {
                return $this.NewDecision(
                    'KeepCurrent',
                    $CurrentBranch.Name,
                    'Current branch still exists and has latest activity.'
                )
            }

            if ($Unattended) {
                return $this.NewDecision(
                    'KeepCurrentUnattended',
                    $CurrentBranch.Name,
                    'Current branch still exists, so unattended mode keeps it.'
                )
            }

            $Reason = 'Branch {0} has newer activity than current branch {1}.' -f
                $MostRecentBranch.Name,
                $CurrentBranch.Name

            return $this.NewDecision(
                'AskMoveToNewer',
                $CurrentBranch.Name,
                $Reason
            )
        }

        if (-not [string]::IsNullOrWhiteSpace($Source.CurrentBranch)) {
            return $this.NewDecision(
                'MoveFromMissingCurrent',
                $MostRecentBranch.Name,
                'Current branch no longer exists, so most recent active branch is selected.'
            )
        }

        if ($DefaultBranch -and $MostRecentBranch.Name -ne $DefaultBranch.Name -and -not $Unattended) {
            $Reason = 'Branch {0} has newer activity than default branch {1}.' -f
                $MostRecentBranch.Name,
                $DefaultBranch.Name

            return $this.NewDecision(
                'AskMoveFromDefault',
                $DefaultBranch.Name,
                $Reason
            )
        }

        if ($DefaultBranch) {
            return $this.NewDecision(
                'UseDefault',
                $DefaultBranch.Name,
                'No branch is deployed yet, so default branch is selected.'
            )
        }

        return $this.NewDecision(
            'UseMostRecent',
            $MostRecentBranch.Name,
            'No default branch exists, so most recent active branch is selected.'
        )
    }

    hidden [pscustomobject] NewDecision(
        [string]$Action,
        [string]$SelectedBranch,
        [string]$Reason
    ) {
        return [pscustomobject]@{
            Action = $Action
            SelectedBranch = $SelectedBranch
            Reason = $Reason
        }
    }
}

class DeploymentStageRunner {
    [DeploymentReport]$Report
    [bool]$ReportOnly

    DeploymentStageRunner([DeploymentReport]$Report, [bool]$ReportOnly) {
        $this.Report = $Report
        $this.ReportOnly = $ReportOnly
    }

    [void] RunStage(
        [pscustomobject]$Environment,
        [pscustomobject]$Tool,
        [pscustomobject]$HostItem,
        [pscustomobject]$Stage
    ) {
        foreach ($Step in @($Stage.Steps)) {
            $Result = [pscustomobject]@{
                Environment = $Environment.Name
                Host = $HostItem.Name
                Tool = $Tool.Name
                Stage = $Stage.Name
                Step = $Step.Name
                Account = $Stage.Account
                Changed = -not $this.ReportOnly
                Passed = $true
                Message = ''
            }

            if ($this.ReportOnly) {
                $Result.Message = 'Report-only mode would run this step through the shared execution path.'
            } else {
                $Result.Message = 'Simulated step completed through the shared execution path.'
            }

            $this.Report.StageResults.Add($Result)
            $this.Report.AddMessage(
                $Environment.Name,
                $HostItem.Name,
                $Tool.Name,
                $Stage.Name,
                'Info',
                $Result.Message
            )
        }
    }
}

function Import-DeploymentToolConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        Write-Error -Message ('Configuration file was not found: {0}' -f $Path) -ErrorAction Stop
    }

    return Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
}

function Test-DeploymentToolConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config
    )

    $Validator = [DeploymentConfigValidator]::new($Config)
    return $Validator.Test()
}

function Invoke-DeploymentToolPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Config,

        [switch]$ReportOnly,

        [switch]$Unattended
    )

    $Report = [DeploymentReport]::new()
    $Findings = Test-DeploymentToolConfig -Config $Config
    $Failures = @($Findings | Where-Object { $_.Result -eq 'Fail' })

    foreach ($Finding in $Findings) {
        $Level = if ($Finding.Result -eq 'Fail') { 'Error' } else { 'Info' }
        $Report.AddMessage('Configuration', 'Local', 'All', 'Validation', $Level, $Finding.Message)
    }

    if ($Failures.Count -gt 0) {
        return $Report.ToObject()
    }

    $Resolver = [BranchVersionResolver]::new()
    $Runner = [DeploymentStageRunner]::new($Report, $ReportOnly.IsPresent)

    foreach ($Tool in @($Config.Tools)) {
        $Environment = @($Config.Environments | Where-Object { $_.Name -eq $Tool.Environment })[0]
        $Decision = $Resolver.Resolve($Tool.Source, $Unattended)
        $Report.Decisions.Add([pscustomobject]@{
            Environment = $Environment.Name
            Tool = $Tool.Name
            Action = $Decision.Action
            SelectedBranch = $Decision.SelectedBranch
            Reason = $Decision.Reason
        })

        foreach ($HostItem in @($Tool.Hosts)) {
            $Report.AddMessage(
                $Environment.Name,
                $HostItem.Name,
                $Tool.Name,
                'Source',
                'Info',
                ('Selected branch {0}. {1}' -f $Decision.SelectedBranch, $Decision.Reason)
            )

            foreach ($Stage in @($Tool.Stages)) {
                $Runner.RunStage($Environment, $Tool, $HostItem, $Stage)
            }
        }
    }

    return $Report.ToObject()
}

function Export-DeploymentToolReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Report,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $Folder = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($Folder)) {
        New-Item -Path $Folder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Report | ConvertTo-Json -Depth 8 | Set-Content -Path $Path -Encoding utf8 -ErrorAction Stop
}

Export-ModuleMember -Function Import-DeploymentToolConfig
Export-ModuleMember -Function Test-DeploymentToolConfig
Export-ModuleMember -Function Invoke-DeploymentToolPlan
Export-ModuleMember -Function Export-DeploymentToolReport
