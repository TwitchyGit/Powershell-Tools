# PowerShell training course samples

This folder is a practical PowerShell course. It starts with small language examples, then moves into file handling, modules, deployment, directory-service style work and CyberArk-style operational samples.

The samples are training tools. Scripts that model Git, AD, CyberArk, backup or VS Code package work use local sample data unless a file says otherwise.

## Course units

1. `01-Language-Fundamentals`
   Syntax, control flow, operators, types, classes, jobs and parallel loops.

2. `02-Objects-And-Data`
   Objects, hashtables, calculated properties, sorting, CSV, JSON, XML and PSD1 parsing.

3. `03-Pipeline-And-Functions`
   Pipeline input, function output, parameter validation, streams, errors and `ShouldProcess`.

4. `04-Files-Environment-And-Runtime`
   Paths, files, providers, environment values, native exit codes, REST calls and secure strings.

5. `05-Modules-And-Configuration`
   Shared helpers, configuration files, module imports and the course check script.

6. `06-Deployment-And-Git-Training`
   A local Git-style deployment flow with setup, package preparation, deployment and receipt checks.

7. `07-Operations-And-Directory-Services`
   AD-shaped samples for account checks, computer scans, group membership and GUI versus CLI input.

8. `08-CyberArk-Backup-And-Compatibility`
   CyberArk-shaped samples, backup and restore flow, AutoSys runfile output, VS Code package handling and compatibility checks.

## Suggested path

Run the first four units script by script. They are small and mostly independent.

Use `05-Modules-And-Configuration` before the applied units because later deployment samples share its helper module and environment data.

Run the local deployment flow:

```powershell
cd ./06-Deployment-And-Git-Training
./Deploy-GitRepository.ps1
```

Run the deployment check:

```powershell
cd ../05-Modules-And-Configuration
./Check.ps1
```

## Safety notes

- The deployment training scripts do not call `git`, `ssh` or a network command.
- AD-shaped samples do not prove live Active Directory behavior unless run against a real AD environment.
- CyberArk-shaped samples do not prove live PVWA behavior unless run against PVWA with real configuration.
- Static checks on macOS do not replace Windows PowerShell, AutoSys, AD or CyberArk validation.
