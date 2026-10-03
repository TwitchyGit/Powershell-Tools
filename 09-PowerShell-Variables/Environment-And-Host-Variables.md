# Environment and Host Variables

## Environment variables (`$env:`)

Read and write through the `Env:` drive.

```powershell
$env:COMPUTERNAME
$env:USERNAME
$env:USERDOMAIN
$env:TEMP
$env:PATH
$env:ProgramFiles
$env:SystemRoot
$env:GDM_ApiToken = $Token
```

| Variable | Meaning |
|---|---|
| `$env:COMPUTERNAME` | Host name (Windows) |
| `$env:USERNAME` and `$env:USERDOMAIN` | Current user and domain |
| `$env:TEMP` and `$env:TMP` | Temp folder |
| `$env:PATH` | Search path for executables. Separator is `;` on Windows and `:` on Linux and macOS |
| `$env:ProgramFiles` and `${env:ProgramFiles(x86)}` | Program Files folders. The x86 name needs braces |
| `$env:SystemRoot` | Windows folder |
| `$env:USERPROFILE` | User profile folder on Windows |

Notes:

- Changes to `$env:` last for the current process and its child processes only. Use `[Environment]::SetEnvironmentVariable("Name", "Value", "Machine")` for a permanent change.
- Environment variables are plain text. Do not leave tokens in them longer than needed. Remove after use with `Remove-Item Env:\GDM_ApiToken`.
- An environment variable is a convenient way to pass a value into a relaunched child process.
- Do not confuse `$env:` with a variable named `$Env`. A variable called `$Env` is legal and separate, but avoid it because it reads like the drive.

## Version and platform

| Variable | Meaning |
|---|---|
| `$PSVersionTable` | Table with `PSVersion`, `PSEdition`, `OS`, `Platform` |
| `$PSVersionTable.PSVersion.Major` | Major version, for example 5 or 7 |
| `$PSVersionTable.PSEdition` | `Desktop` (Windows PowerShell) or `Core` (PowerShell 7) |
| `$IsWindows` `$IsLinux` `$IsMacOS` | Platform flags in PowerShell 6 and later. Not defined in Windows PowerShell 5.1 |
| `$PSHOME` | Folder where PowerShell is installed |

Check platform safely in 5.1:

```powershell
$OnWindows = ($PSVersionTable.PSEdition -eq "Desktop") -or $IsWindows
```

## Paths and profile

| Variable | Meaning |
|---|---|
| `$HOME` | User home folder |
| `$PROFILE` | Path of the current user profile script |
| `$PROFILE.AllUsersAllHosts` | Profile for all users and hosts |
| `$PSModulePath` is `$env:PSModulePath` | Folders searched for modules |

## Host

| Variable | Meaning |
|---|---|
| `$Host.Name` | Host name, for example `ConsoleHost` |
| `$Host.UI.RawUI.WindowSize` | Console window size |
| `$Host.UI.RawUI.WindowTitle` | Console title. Settable |
| `$Host.Version` | Host version |
| `$Host.PrivateData` | Host colour settings |

## Common checks

Elevated session on Windows:

```powershell
$Principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$IsAdmin = $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
```

Interactive session:

```powershell
$Interactive = [Environment]::UserInteractive -and -not ([Environment]::GetCommandLineArgs() -contains "-NonInteractive")
```
