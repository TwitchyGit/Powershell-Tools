<#
.SYNOPSIS
Runs local smoke tests for selected course scripts.

.DESCRIPTION
The script runs safe local samples in child PowerShell processes and reports exit codes.

.NOTES
This script is training material. It does not validate live AD, PVWA, AutoSys, Git remote or Windows behavior.
#>
[CmdletBinding()]
param(
    [string[]]
    $ExcludePattern = @(
        'Check-User-GUI.ps1'
    )
)

try {
    $CourseRoot = $PSScriptRoot
    $PowerShellCommand = (Get-Process -Id $PID).Path
    $ScriptFiles = Get-ChildItem -Path $CourseRoot -Recurse -Filter '*.ps1' -File |
        Where-Object { $_.Name -notin @('Invoke-CourseSmokeTest.ps1', 'Invoke-CourseCleanup.ps1') } |
        Where-Object {
            $Name = $_.Name
            -not ($ExcludePattern | Where-Object { $Name -like $_ })
        } |
        Sort-Object -Property FullName

    $Results = foreach ($ScriptFile in $ScriptFiles) {
        $RelativePath = $ScriptFile.FullName.Replace($CourseRoot, '.').TrimStart('/').TrimStart('\')
        $Timer = [System.Diagnostics.Stopwatch]::StartNew()
        $Output = & $PowerShellCommand -NoProfile -File $ScriptFile.FullName 2>&1
        $ExitCode = $LASTEXITCODE
        $Timer.Stop()

        [pscustomobject]@{
            Script = $RelativePath
            ExitCode = $ExitCode
            Passed = $ExitCode -eq 0
            DurationMs = [int]$Timer.ElapsedMilliseconds
            OutputLines = @($Output).Count
        }
    }

    $Results
    $Failed = @($Results | Where-Object { -not $_.Passed })

    [pscustomobject]@{
        Stage = 'Summary'
        Scripts = @($Results).Count
        Failed = $Failed.Count
        Passed = $Failed.Count -eq 0
    }

    if ($Failed.Count -gt 0) {
        Write-Error -Message 'One or more course smoke tests failed.' -ErrorAction Stop
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
