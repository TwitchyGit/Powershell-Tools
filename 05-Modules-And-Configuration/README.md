# Modules and configuration

This unit introduces shared helper modules and data-file configuration.

`PSFunctions.psm1` owns shared course paths, environment loading, folder creation, logging and token checks. `Environment.psd1` stores local training settings. `Check.ps1` parses the full course tree and imports the shared modules.

Process focus:

- `Test-PowershellDataFile.ps1` validates the required PSD1 sections before other units rely on them.
- `Set-Conf.ps1` writes a named training setting and confirms the output file exists.
- `Set-Conf-User.ps1` writes a user configuration record with role, source and timestamp evidence.
- `Configure.ps1` writes restore configuration for later restore-shaped samples.
- `Caller.ps1` runs training scripts across units and records script-level exit codes.

Useful checks:

```powershell
./Test-PowershellDataFile.ps1
./Check.ps1
./Caller.ps1
```

Training aim: separate reusable behavior from entry scripts, then keep configuration as data rather than hard-coded values.
