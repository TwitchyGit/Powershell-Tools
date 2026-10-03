# Automatic Variables

PowerShell creates and updates these. Do not assign to them unless noted.

| Variable | Meaning | Gotcha |
|---|---|---|
| `$?` | `$true` if the last statement succeeded | Reset by every statement, so read it on the very next line |
| `$LASTEXITCODE` | Exit code of the last native exe or `.ps1` that called `exit N` | Not set by cmdlets. A script that never calls `exit` leaves the old value in place |
| `$_` and `$PSItem` | Current object in a pipeline, `Where-Object`, `ForEach-Object` or `catch` | In `catch` it is the error record |
| `$args` | Unbound arguments passed to a script or function | Empty when the function declares a `param` block and receives only named values |
| `$input` | Enumerator of pipeline input inside a function without `begin/process/end` | Can be read once |
| `$Error` | Array of recent errors, newest first | `$Error[0]` is the latest. Clear with `$Error.Clear()` |
| `$null` | The null value | Put it on the left in comparisons: `$null -eq $Value` |
| `$true` and `$false` | Boolean values | The string `"False"` is truthy because it is not empty |
| `$PID` | Process ID of the current session | |
| `$PSBoundParameters` | Hashtable of parameters the caller actually passed | Use it to splat to another call or test if a parameter was supplied |
| `$PSCmdlet` | Cmdlet object inside an advanced function | Gives `ShouldProcess`, `ParameterSetName`, `WriteObject` |
| `$MyInvocation` | Details about how the current command was called | See [Script-And-Location-Variables.md](Script-And-Location-Variables.md) |
| `$StackTrace` | Last stack trace | Rarely useful. Prefer `$_.ScriptStackTrace` in `catch` |
| `$Matches` | Hashtable filled by `-match` | Only set when the left side is a scalar |
| `$ExecutionContext` | Engine intrinsics | Used for `ExpandString` and invoking commands |
| `$ForEach` | Enumerator inside a `foreach` statement | Different from `ForEach-Object` |
| `$Switch` | Enumerator inside a `switch` statement | |
| `$NestedPromptLevel` | Depth of nested prompts | |
| `$ConsoleFileName` | Console file used in the session | |

## Exit code pattern

```powershell
$global:LASTEXITCODE = 0
& $Command
$Succeeded = ($LASTEXITCODE -eq 0)
```

Reset first, because a stale value from an earlier call can mask a silent success or failure.

## Truthiness

False values: `$false`, `$null`, `0`, `""`, `@()`.
True values: any non-empty string (including `"False"`), any non-zero number, any non-empty array.

## Error record fields inside catch

```powershell
try {
    Invoke-Action
} catch {
    $_.Exception.Message
    $_.ScriptStackTrace
    $_.InvocationInfo.ScriptLineNumber
}
```
