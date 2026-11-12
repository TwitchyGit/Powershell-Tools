<#
.SYNOPSIS
    Runs a set of checks in parallel and writes one summary.

.DESCRIPTION
    A suite is a named list of checks in the Suites section of Config\CheckSettings.psm1.
    The runner starts each check in its own PowerShell job, up to MaxParallel at one time.
    It passes -Simulate, -Verbose, -Debug, -OutputDirectory and credentials to the checks.

    A check counts as failed if its exit code is not 0, if it times out or if its script is missing.
    The runner exits with 0 if all checks passed and with 1 if any check failed.

    Simulation: the runner passes -Simulate to every check. Nothing is changed and no
    files are written. The output of each check is shown on the console.

.PARAMETER Suite
    Name of the suite to run. Default is Health.

.PARAMETER Check
    Run only the checks with these names (the Name key in the suite).

.PARAMETER List
    Show the suites and checks, then stop.

.PARAMETER ApiCredential
    Account for checks that open a CyberArk API session. If you do not give it and the
    session is interactive, the runner asks for it (not in simulation).

.PARAMETER RemoteCredential
    Account for PowerShell remoting. Default is the current user.

.PARAMETER NoPrompt
    Never ask for credentials.

.PARAMETER MaxParallel
    Overrides Runner.MaxParallel.

.PARAMETER Simulate
    Makes no changes. No report files are written.

.EXAMPLE
    .\Run-Checks.ps1 -List

.EXAMPLE
    .\Run-Checks.ps1 -Suite Health -Simulate -Verbose

.EXAMPLE
    .\Run-Checks.ps1 -Suite Logs -Check LogArchive-CPM,LogArchive-PSM
#>
[CmdletBinding()]
param(
    [string]$Suite = 'Health',
    [string[]]$Check,
    [switch]$List,
    [switch]$Simulate,
    [pscredential]$ApiCredential,
    [pscredential]$RemoteCredential,
    [switch]$NoPrompt,
    [int]$MaxParallel,
    [string]$OutputDirectory
)

if ($PSBoundParameters.ContainsKey('Debug')) { $DebugPreference = 'SilentlyContinue' }

$settingsModule = $env:ONPREM_CHECKS_SETTINGS
if ([string]::IsNullOrWhiteSpace($settingsModule)) {
    $settingsModule = Join-Path -Path $PSScriptRoot -ChildPath 'Config\CheckSettings.psm1'
}
Import-Module -Name $settingsModule -Force -ErrorAction Stop

$settings = Get-CheckSettings

if ($List) {
    foreach ($name in ($settings.Suites.Keys | Sort-Object)) {
        Write-Host ("Suite: {0}" -f $name)
        foreach ($entry in $settings.Suites[$name]) {
            Write-Host ("    {0}  ({1})" -f $entry.Name, $entry.Script)
        }
    }
    exit 0
}

if (-not $settings.Suites.ContainsKey($Suite)) {
    Write-Error ("Suite '{0}' is not in the settings. Known suites: {1}." -f $Suite, ($settings.Suites.Keys -join ', '))
    exit 1
}

$baseDirectory = $OutputDirectory
if ([string]::IsNullOrWhiteSpace($baseDirectory)) { $baseDirectory = Join-Path -Path $settings.Paths.OutputRoot -ChildPath 'Runs' }
$sessionDirectory = Join-Path -Path $baseDirectory -ChildPath ('Run_{0:yyyyMMdd_HHmmss}' -f (Get-Date))

try {
    $ctx = Start-Check -Name 'Run-Checks' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $sessionDirectory
} catch {
    Write-Error $_.Exception.Message
    exit 1
}

$checksDirectory = $settings.Paths.ChecksDirectory
if ([string]::IsNullOrWhiteSpace($checksDirectory)) { $checksDirectory = Join-Path -Path $PSScriptRoot -ChildPath 'Checks' }

# Pick the checks to run.
$entries = @($settings.Suites[$Suite])
if (@($Check | Where-Object { $_ }).Count -gt 0) {
    $entries = @($entries | Where-Object { $_.Name -in $Check })
    $unknown = @($Check | Where-Object { $_ -notin @($settings.Suites[$Suite] | ForEach-Object { $_.Name }) })
    foreach ($u in $unknown) { Write-CheckLog -Level Warn -Message ("Check '{0}' is not in suite '{1}'." -f $u, $Suite) }
}
if ($entries.Count -eq 0) {
    Write-CheckLog -Level Error -Message 'No checks to run.'
    exit 1
}

# Ask for the API account if a check needs it. Simulation never opens a session, so it never asks.
$needsApi = @($entries | Where-Object { $_.NeedsApiCredential }).Count -gt 0
if ($needsApi -and -not $ApiCredential -and -not $Simulate -and -not $NoPrompt -and [Environment]::UserInteractive) {
    $ApiCredential = Get-Credential -Message 'Enter the account for the CyberArk API session test'
}

$limit = $settings.Runner.MaxParallel
if ($PSBoundParameters.ContainsKey('MaxParallel') -and $MaxParallel -gt 0) { $limit = $MaxParallel }
$timeoutMinutes = $settings.Runner.CheckTimeoutMinutes

Write-CheckLog -Level Info -Message ("Suite '{0}': {1} check(s). Up to {2} at one time." -f $Suite, $entries.Count, $limit)
if (-not $Simulate) { Write-CheckLog -Level Info -Message ("Output folder: {0}" -f $sessionDirectory) }

# The job runs one check script and returns its exit code and its output text.
$jobScript = {
    param([string]$ScriptPath, [hashtable]$ScriptParams, [string]$WorkingDirectory)
    $code = 1
    $text = ''
    try {
        Set-Location -LiteralPath $WorkingDirectory
        $global:LASTEXITCODE = $null
        $output = @(& $ScriptPath @ScriptParams *>&1)
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 1 }
        $text = (($output | ForEach-Object { "$_" }) -join "`r`n")
    } catch {
        $code = 1
        $text = 'Script error: ' + $_.Exception.Message
    }
    [pscustomobject]@{ ExitCode = [int]$code; Output = $text }
}

# Build the work list.
$queue = New-Object System.Collections.Queue
foreach ($entry in $entries) {
    $scriptPath = Join-Path -Path $checksDirectory -ChildPath $entry.Script
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Add-Finding -Target $env:COMPUTERNAME -Item $entry.Name -Status Fail -Message ("Script not found: {0}" -f $scriptPath)
        continue
    }

    $params = @{}
    if ($entry.Params) { foreach ($key in $entry.Params.Keys) { $params[$key] = $entry.Params[$key] } }
    if ($Simulate) { $params['Simulate'] = $true }
    if ($ctx.Verbose) { $params['Verbose'] = $true }
    if ($ctx.Debug) { $params['Debug'] = $true }
    $params['OutputDirectory'] = $sessionDirectory
    if ($entry.NeedsApiCredential -and $ApiCredential) { $params['ApiCredential'] = $ApiCredential }
    $usesRemoting = $true
    if ($entry.ContainsKey('UsesRemoting')) { $usesRemoting = [bool]$entry.UsesRemoting }
    if ($usesRemoting -and $RemoteCredential) { $params['RemoteCredential'] = $RemoteCredential }

    $queue.Enqueue([pscustomobject]@{ Entry = $entry; ScriptPath = $scriptPath; Params = $params })
}

$running = @()
$summary = New-Object System.Collections.ArrayList

function Complete-RunningCheck {
    param($Run, [bool]$TimedOut)

    $entry = $Run.Entry.Entry
    $seconds = [math]::Round(((Get-Date) - $Run.Started).TotalSeconds, 1)
    $exitCode = 1
    $text = ''
    $status = 'Failed'

    if ($TimedOut) {
        Stop-Job -Job $Run.Job -ErrorAction SilentlyContinue
        $status = 'TimedOut'
        $text = 'The check did not finish in {0} minute(s) and was stopped.' -f $timeoutMinutes
    } else {
        $payload = @(Receive-Job -Job $Run.Job -ErrorAction SilentlyContinue) | Select-Object -Last 1
        if ($null -ne $payload -and $null -ne $payload.ExitCode) {
            $exitCode = [int]$payload.ExitCode
            $text = [string]$payload.Output
            if ($exitCode -eq 0) { $status = 'Passed' }
        } else {
            $reason = ''
            if ($Run.Job.ChildJobs.Count -gt 0 -and $Run.Job.ChildJobs[0].JobStateInfo.Reason) {
                $reason = $Run.Job.ChildJobs[0].JobStateInfo.Reason.Message
            }
            $text = 'The job returned no result. ' + $reason
        }
    }
    Remove-Job -Job $Run.Job -Force -ErrorAction SilentlyContinue

    $ignored = [bool]$entry.IgnoreExitCode
    Write-CheckLog -Level Info -Message ("{0}: {1} (exit code {2}, {3} s)" -f $entry.Name, $status, $exitCode, $seconds)
    if ($Simulate -or $ctx.Verbose -or ($status -ne 'Passed')) {
        if ($text) { Write-Host $text }
    }

    if ($status -eq 'Passed') {
        Add-Finding -Target $env:COMPUTERNAME -Item $entry.Name -Status Pass -Message ('Exit code 0 in {0} s.' -f $seconds)
    } elseif ($ignored) {
        Add-Finding -Target $env:COMPUTERNAME -Item $entry.Name -Status Info -Message ('{0}. Exit code {1} ignored by the suite.' -f $status, $exitCode)
    } else {
        Add-Finding -Target $env:COMPUTERNAME -Item $entry.Name -Status Fail -Message ('{0}. Exit code {1} after {2} s.' -f $status, $exitCode, $seconds)
    }
}

try {
    while ($queue.Count -gt 0 -or $running.Count -gt 0) {
        while ($queue.Count -gt 0 -and $running.Count -lt $limit) {
            $next = $queue.Dequeue()
            Write-CheckLog -Level Verbose -Message ("Starting {0}." -f $next.Entry.Name)
            $job = Start-Job -ScriptBlock $jobScript -ArgumentList $next.ScriptPath, $next.Params, $PSScriptRoot
            $running += [pscustomobject]@{ Entry = $next; Job = $job; Started = Get-Date }
        }

        Start-Sleep -Milliseconds 500

        $stillRunning = @()
        foreach ($run in $running) {
            $elapsedMinutes = ((Get-Date) - $run.Started).TotalMinutes
            $finished = $run.Job.State -in @('Completed', 'Failed', 'Stopped')
            if ($finished) {
                Complete-RunningCheck -Run $run -TimedOut $false
            } elseif ($elapsedMinutes -gt $timeoutMinutes) {
                Complete-RunningCheck -Run $run -TimedOut $true
            } else {
                $stillRunning += $run
            }
        }
        $running = $stillRunning
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Runner' -Status Error -Message $_.Exception.Message
    foreach ($run in $running) { Remove-Job -Job $run.Job -Force -ErrorAction SilentlyContinue }
} finally {
    # Remove credentials from memory.
    $ApiCredential = $null
    $RemoteCredential = $null
    foreach ($item in @($queue.ToArray())) { $item.Params.Clear() }
}

exit (Complete-Check)
