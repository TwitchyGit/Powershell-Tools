# Files, environment and runtime

This unit connects PowerShell syntax to the host system. It covers paths, content, providers, environment variables, process inspection, native command exit codes, REST requests and secure strings.

Process focus:

- `Diagnostic.ps1` collects local runtime facts and marks failed checks.
- `EnvironmentVariables.ps1` reads environment values and falls back to `.NET` temp-path discovery.
- `FileContent.ps1` writes, appends, reads and removes a temporary training file.
- `FileDiscovery.ps1` samples files from the unit folder and summarizes bytes.
- `JoinPath.ps1` compares provider-aware path building with a manual example.
- `NativeCommandExitCode.ps1` captures native exit code before a cmdlet failure can distract from it.
- `ProcessInspection.ps1` reads process objects without changing the host.
- `ProvidersAndDrives.ps1` samples providers and drives.
- `RestApiRequest.ps1` shows request shape without calling a live API.
- `SecureString.ps1` explains the training boundary for secret-shaped values.

Useful checks:

```powershell
./JoinPath.ps1
./FileContent.ps1
./NativeCommandExitCode.ps1
./Diagnostic.ps1
./RestApiRequest.ps1
```

Training aim: distinguish PowerShell errors from native process exit codes and use provider-aware paths instead of string-built file paths.
