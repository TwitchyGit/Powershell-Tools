# Preference Variables

Preference variables change how the engine reacts. Set them at the top of a script or around one block.

| Variable | Values | Effect |
|---|---|---|
| `$ErrorActionPreference` | `Continue` (default) `Stop` `SilentlyContinue` `Ignore` `Inquire` | What to do on non-terminating errors. `Stop` turns them into terminating errors that `catch` can handle |
| `$WarningPreference` | `Continue` `SilentlyContinue` `Stop` `Inquire` | Controls `Write-Warning` |
| `$VerbosePreference` | `SilentlyContinue` (default) `Continue` | Shows `Write-Verbose` output. Set by `-Verbose` on advanced functions |
| `$DebugPreference` | `SilentlyContinue` (default) `Continue` `Inquire` | Shows `Write-Debug` output. Set by `-Debug` |
| `$InformationPreference` | `SilentlyContinue` (default) `Continue` | Shows `Write-Information` output without needing `-InformationAction` |
| `$ProgressPreference` | `Continue` (default) `SilentlyContinue` | Progress bar. Setting `SilentlyContinue` speeds up `Invoke-WebRequest` and large copies |
| `$ConfirmPreference` | `High` (default) `Medium` `Low` `None` | When `ShouldProcess` prompts |
| `$WhatIfPreference` | `$false` (default) `$true` | `$true` makes supporting cmdlets report instead of act |
| `$OutputEncoding` | Encoding object | Encoding used when piping text to native programs |
| `$MaximumHistoryCount` | Integer | Size of session history |
| `$PSDefaultParameterValues` | Hashtable | Default parameter values, for example `@{ "Out-File:Encoding" = "utf8" }` |
| `$ErrorView` | `NormalView` `ConciseView` | How errors display |

## Scoping a preference to one block

Preference variables follow normal scope rules. A change inside a function lasts until the function returns.

```powershell
function Invoke-Step {
    [CmdletBinding()]
    param()

    $ErrorActionPreference = "Stop"
    Invoke-Action
}
```

## Common patterns

Stop on any error in an entry script:

```powershell
$ErrorActionPreference = "Stop"
```

Restore after a block:

```powershell
$Previous = $ErrorActionPreference
$ErrorActionPreference = "Stop"
try {
    & $Command
} finally {
    $ErrorActionPreference = $Previous
}
```

Per-call override:

```powershell
Get-Item -Path $Path -ErrorAction SilentlyContinue
```

## Notes

- `$ErrorActionPreference = "Stop"` does not apply to native executables. Check `$LASTEXITCODE` after `git`, `robocopy` and similar.
- In PowerShell 7.3 and later, `$PSNativeCommandUseErrorActionPreference = $true` makes a non-zero native exit code raise an error that follows `$ErrorActionPreference`.
- `-Verbose` and `-Debug` on a function set the matching preference variable inside that function and in the functions it calls.
