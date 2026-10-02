# 09 PowerShell Variables

Reference for the PowerShell variables that matter in deployment and operations scripts.

| File | Covers |
|---|---|
| [AUTOMATIC-VARIABLES.md](AUTOMATIC-VARIABLES.md) | Variables PowerShell sets for you: `$?`, `$LASTEXITCODE`, `$_`, `$args`, `$PWD` and others |
| [SCRIPT-AND-LOCATION-VARIABLES.md](SCRIPT-AND-LOCATION-VARIABLES.md) | Where a script lives versus where it was started: `$PSScriptRoot`, `$PSCommandPath`, `$PWD`, `$MyInvocation` |
| [PREFERENCE-VARIABLES.md](PREFERENCE-VARIABLES.md) | Variables that change engine behaviour: `$ErrorActionPreference`, `$VerbosePreference`, `$InformationPreference` and others |
| [ENVIRONMENT-AND-HOST-VARIABLES.md](ENVIRONMENT-AND-HOST-VARIABLES.md) | `$env:` drive, `$PSVersionTable`, `$IsWindows`, `$HOME`, `$PROFILE`, `$Host` |
| [SCOPE-AND-MODULE-VARIABLES.md](SCOPE-AND-MODULE-VARIABLES.md) | `$script:`, `$global:`, `$local:`, `$using:`, module variables and exports |

## Quick picks

- Folder the script file lives in: `$PSScriptRoot`
- Folder the user launched from: `$PWD`
- Did the last native command or script succeed: `$LASTEXITCODE -eq 0`
- Make every error stop the script: `$ErrorActionPreference = "Stop"`
- Value from the calling session inside `Invoke-Command`: `$using:Name`
- Private state shared by functions in one `.psm1`: `$script:Name`
