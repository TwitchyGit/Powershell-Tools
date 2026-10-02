# 09 PowerShell Variables

Reference for the PowerShell variables that matter in deployment and operations scripts.

| File | Covers |
|---|---|
| [Automatic-Variables.md](Automatic-Variables.md) | Variables PowerShell sets for you: `$?`, `$LASTEXITCODE`, `$_`, `$args`, `$PWD` and others |
| [Script-And-Location-Variables.md](Script-And-Location-Variables.md) | Where a script lives versus where it was started: `$PSScriptRoot`, `$PSCommandPath`, `$PWD`, `$MyInvocation` |
| [Preference-Variables.md](Preference-Variables.md) | Variables that change engine behaviour: `$ErrorActionPreference`, `$VerbosePreference`, `$InformationPreference` and others |
| [Environment-And-Host-Variables.md](Environment-And-Host-Variables.md) | `$env:` drive, `$PSVersionTable`, `$IsWindows`, `$HOME`, `$PROFILE`, `$Host` |
| [Scope-And-Module-Variables.md](Scope-And-Module-Variables.md) | `$script:`, `$global:`, `$local:`, `$using:`, module variables and exports |

## Quick picks

- Folder the script file lives in: `$PSScriptRoot`
- Folder the user launched from: `$PWD`
- Did the last native command or script succeed: `$LASTEXITCODE -eq 0`
- Make every error stop the script: `$ErrorActionPreference = "Stop"`
- Value from the calling session inside `Invoke-Command`: `$using:Name`
- Private state shared by functions in one `.psm1`: `$script:Name`
