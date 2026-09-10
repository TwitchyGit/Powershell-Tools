#requires -Version 5.1

<#
.SYNOPSIS
Audits a script for migration from Windows PowerShell 5.1 to PowerShell 7.6.3.

.DESCRIPTION
The supplied script is parsed but never executed. The auditor launches clean child
processes for Windows PowerShell 5.1 and PowerShell 7, inventories their environments
and compares parsing, commands, parameters, modules, profiles and known compatibility
risks. Literal local dot-sourced scripts and path-based module dependencies are also
parsed when they can be resolved without executing the supplied code.

The report separates blocking findings, warnings and items needing a controlled
runtime test. Static analysis cannot prove every possible runtime path, external
dependency or dynamically constructed command.

.PARAMETER ScriptPath
The .ps1, .psm1 or .psd1 file to audit.

.PARAMETER PowerShell7Path
Path or command name for the target pwsh.exe. The default is pwsh.exe.

.PARAMETER WindowsPowerShellPath
Path to Windows PowerShell 5.1. The default is the standard Windows location.

.PARAMETER TargetPowerShellVersion
Exact target version. The default is 7.6.3.

.PARAMETER OutputDirectory
Directory for the Markdown, JSON and CSV reports. A timestamped directory in the
current directory is used by default.

.PARAMETER IncludeProfileSessions
Also starts each shell with its normal profiles enabled. Profiles themselves can run
arbitrary user code, so this is opt-in. Profile files are inspected statically even
when this switch is not used.

.PARAMETER AllowTargetVersionMismatch
Completes the comparison against the installed pwsh version when it is not exactly
the requested target. The mismatch remains a blocking finding in the report.

.EXAMPLE
.\Test-PS51ToPS763Compatibility.ps1 -ScriptPath C:\Scripts\Job.ps1

.EXAMPLE
.\Test-PS51ToPS763Compatibility.ps1 -ScriptPath C:\Scripts\Job.ps1 -IncludeProfileSessions

.NOTES
Exit code 0 means that the audit completed with no blocking findings. Exit code 1
means that the audit failed or at least one blocking finding was detected. Warnings
and manual-review findings do not change the exit code.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string]$ScriptPath,

    [string]$PowerShell7Path = 'pwsh.exe',

    [string]$WindowsPowerShellPath = $(
        if ($env:WINDIR) {
            Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        }
        else {
            'powershell.exe'
        }
    ),

    [version]$TargetPowerShellVersion = '7.6.3',

    [string]$OutputDirectory,

    [switch]$IncludeProfileSessions,

    [switch]$AllowTargetVersionMismatch
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Resolve-ExecutablePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return (Resolve-Path -LiteralPath $Path).ProviderPath
    }

    $command = Get-Command -Name $Path -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($command) {
        return $command.Source
    }