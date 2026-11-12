# CyberArk On-Premises Checks

A set of PowerShell 5.1 health checks for on-premises CyberArk components: Vault, CPM, PVWA, PSM, CCP, Synchronizer, PSMP and PTA.
Each check runs alone or through `Run-Checks.ps1`.
Each check has a verbose mode, a debug mode and a simulation mode.

## Layout

```
Run-Checks.ps1                  Runs a suite of checks in parallel
Config\CheckSettings.psm1       All user settings and all shared helper code
Checks\Check-*.ps1              One script for each check
```

Every check imports only `Config\CheckSettings.psm1`.
All names, paths, limits, rules and suites are in the USER SETTINGS section of that file.

## Set-up

1. Open `Config\CheckSettings.psm1`.
2. Replace the example server names, paths, service names, ports and rules with your own values.
3. Set `Configured` to `$true`.
4. Set `Paths.OutputRoot` to a folder that the account that runs the checks can write to.
5. Make sure PowerShell remoting (WinRM) works from the run computer to the Windows component servers.

To keep your settings outside the repository, copy the module to another place and set the environment variable `ONPREM_CHECKS_SETTINGS` to its full path.

## Checks

| Script | What it tests |
| --- | --- |
| `Check-EndpointHealth.ps1` | DNS, TCP ports, web health probe and an API logon and logoff |
| `Check-ServiceState.ps1` | Windows services of each role are running. Can start stopped services |
| `Check-StorageCapacity.ps1` | Free disk space against warning and failure limits |
| `Check-EventLogErrors.ps1` | Count of recent error events, with ignore rules and the top repeated events |
| `Check-EventLogCollect.ps1` | Exports recent events to CSV files |
| `Check-LicenseServer.ps1` | Remote Desktop licensing mode, license servers and free licenses on session hosts |
| `Check-ConfigFiles.ps1` | Configuration files against rules (exists, contains, key value, XML value) |
| `Check-ComponentVersions.ps1` | Installed product versions against a minimum or exact version and across servers |
| `Check-FileParity.ps1` | File hashes of one role compared across its servers |
| `Check-LocalGroupMembership.ps1` | Members of local groups against allowed and required lists |
| `Check-CertificateExpiry.ps1` | Certificate expiry dates in the machine stores |
| `Check-LogArchive.ps1` | Copies recent component logs to a central share |

## Run one check

```powershell
.\Checks\Check-ServiceState.ps1 -Role CPM
.\Checks\Check-StorageCapacity.ps1 -Role PVWA -ComputerName pvwa03.example.local
.\Checks\Check-EndpointHealth.ps1 -Role PVWA -ApiCredential (Get-Credential)
```

Common parameters:

| Parameter | Use |
| --- | --- |
| `-Role` | One or more roles from the settings. The default depends on the check |
| `-ComputerName` | Replaces the server list. Use it with exactly one `-Role` |
| `-Simulate` | Makes no changes (see below) |
| `-Verbose` | Shows every result row, including passes |
| `-Debug` | Shows verbose output plus low-level detail such as URLs, limits and remote calls |
| `-RemoteCredential` | Account for remoting. The default is the current user |
| `-OutputDirectory` | Folder for the CSV and log files |

`-Debug` does not stop to ask for confirmation. It only adds output.

## Run a suite

```powershell
.\Run-Checks.ps1 -List
.\Run-Checks.ps1 -Suite Health
.\Run-Checks.ps1 -Suite Health -Simulate -Verbose
.\Run-Checks.ps1 -Suite Logs -Check LogArchive-CPM,LogArchive-PSM
```

Suites are in the `Suites` section of the settings.
Each entry names a script, optional parameters and these optional flags:

| Key | Meaning |
| --- | --- |
| `NeedsApiCredential` | Pass `-ApiCredential` to the check |
| `UsesRemoting` | Pass `-RemoteCredential` to the check. The default is `$true` |
| `IgnoreExitCode` | Report a non-zero exit code as Info and do not count it as a failure |

The runner starts each check in its own job.
`Runner.MaxParallel` limits how many run at one time.
`Runner.CheckTimeoutMinutes` stops a check that runs too long.

## No SMB

The checks use no SMB file access.

- All remote work uses PowerShell remoting (WinRM, TCP 5985 or 5986). Remote scripts run on the target server. Files travel inside the WinRM session.
- No check opens an administrative share, a UNC path or a mapped drive.
- `Security.BlockSmbPaths` is `$true` by default. While it is on, the output folder and the log archive folder must be local. A UNC path or a mapped network drive stops the check with an error.
- Plan to put the archive on a local disk of the run computer. If you need the files elsewhere, move them with a tool that you approve, outside these checks.
- `Check-EndpointHealth.ps1` does open TCP connections to the ports in your settings. Do not add port 445 to a role if you want to avoid SMB traffic.

## Simulation

`-Simulate` makes no changes. In simulation mode:

- No CSV, log or inventory files are written. The check shows the path it would use.
- `Check-LogArchive.ps1` lists the files it would copy and copies nothing.
- `Check-ServiceState.ps1 -Remediate` shows the services it would start and starts none.
- `Check-EndpointHealth.ps1` skips the API logon, because a logon opens a session.
- `Check-EventLogCollect.ps1` reports how many events it would export.
- Read-only tests (DNS, ports, services, disks, events, files, groups, certificates) still run.
- The settings file can have `Configured` set to `$false`. A live run stops in that case. A simulation only warns.

## Output and exit codes

Each check writes `<Check>_<time>_<pid>.csv` and `.log` to its output folder.
`Run-Checks.ps1` writes everything for one run to `Run_<time>` under `<OutputRoot>\Runs`.

Result statuses are Pass, Info, Skipped, Warn, Fail and Error.
A check exits with 0 if it has no Fail or Error rows and with 1 otherwise.
Set `Runner.TreatWarningAsFailure` to `$true` to count warnings as failures.

## Notes

- Windows-only checks skip roles with `Platform = 'Linux'`. `Check-EndpointHealth.ps1` tests all roles.
- `Check-LogArchive.ps1` reads log files over a WinRM session and writes them to a local folder. It opens no administrative share (`\\server\C$`).
- `Check-ConfigFiles.ps1` runs its rules on the target server. File content does not travel over the network. Set `Sensitive = $true` on a rule to keep a value out of reports.
- Service names, product names, install paths and the web health URL in the settings are starting values. Confirm each one against your own installation.
- The API logon test uses a concurrent session, so it does not end sessions of other users. The password stays in memory only for the time of the call.
