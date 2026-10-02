# Script and Location Variables

## The key difference

| Variable | Meaning |
|---|---|
| `$PSScriptRoot` | Folder that holds the running `.ps1` or `.psm1` file |
| `$PSCommandPath` | Full path of the running script file |
| `$PWD` or `Get-Location` | Folder the user was in when the script started |
| `$MyInvocation.MyCommand.Path` | Full path of the script (older form of `$PSCommandPath`) |
| `$MyInvocation.PSCommandPath` | Path of the caller, not the current script |

`$PSRootDir` is not a PowerShell variable.

Example: the user runs `D:\Tools\Install.ps1` from `C:\Temp`.

- `$PSScriptRoot` is `D:\Tools`
- `$PWD` is `C:\Temp`

## Run from the directory where the script was started

```powershell
$StartDir = $PWD.Path
$LogDir   = Join-Path -Path $StartDir -ChildPath "Logs"
```

Capture it once at the top of the entry script, before any `Push-Location` or `Set-Location`.

## Run from the script's own folder

```powershell
$ModulePath = Join-Path -Path $PSScriptRoot -ChildPath "Config\DeploymentFunctions.psm1"
Import-Module -Name $ModulePath -Force
```

## Rules

- `$PSScriptRoot` is empty when code is pasted into a console. It is only set inside a saved file.
- Inside a `.psm1`, `$PSScriptRoot` is the module folder. `$PWD` is still the caller's current folder, but pass it in as a parameter from the entry script for clarity and testing.
- .NET calls such as `[System.IO.File]::ReadAllText(".\x.txt")` use the process working directory, which can differ from `$PWD`. Always pass absolute paths built with `Join-Path`.
- `Push-Location` and `Set-Location` change `$PWD` for the rest of the script. `Pop-Location` restores it. Wrap in `try/finally` so the restore always runs.

```powershell
Push-Location -LiteralPath $Dest
try {
    & $Command
} finally {
    Pop-Location
}
```

- After a self-update that copies the script elsewhere, `$PSScriptRoot` points to the new location. `$StartDir` stays fixed.

## Invocation details

```powershell
$MyInvocation.MyCommand.Name
$MyInvocation.BoundParameters
$MyInvocation.InvocationName
$MyInvocation.Line
```

Use `$PSCmdlet.MyInvocation` inside an advanced function when you need the function's own invocation rather than the script's.
