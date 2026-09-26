# CyberArk, backup and compatibility

This unit contains CyberArk-shaped and operations-shaped samples. They use local training data only. They do not prove live PVWA, AD, AutoSys or Windows behavior.

## Backup Flow

- `Add-DataCreateLargeSafe.ps1` creates sample account data for a large safe and reports expected record count.
- `Daily-Backup.ps1` checks for a previous daily receipt, writes a daily backup receipt and validates it.
- `Weekly-Backup.ps1` writes a weekly receipt with retention and recovery point detail.

## Restore Flow

- `Get-SafeInventory.ps1` writes safe inventory with classification, restore requirement and account counts.
- `Verify-RestoredSafes.ps1` reads inventory and returns per-safe verification results.
- `Test-Restore.ps1` runs configure, inventory and verification stages with step exit codes.
- `Invoke-AirgapSafeRestore.ps1` runs the restore test and writes a restore receipt.

## PAS Object Flow

- `PAS-CreateObjectList.ps1` creates candidate object rows and reports duplicate-name count.
- `PAS-ProcessFailedObjects.ps1` categorizes failed objects and retry eligibility.
- `Extract-AutoDetectionXML.ps1` extracts CyberArk-style automatic detection XML settings.

## Operations Flow

- `AutosysRunfile.ps1` creates a training runfile with schedule, owner, command and permission fields.
- `Save-VSCodePackages.ps1` creates an offline package manifest with version and checksum evidence.
- `Install-VSCodePackages.ps1` validates the package manifest and reports missing checksum count.
- `Test-PS51ToPS763Compatibility.ps1` demonstrates static compatibility reporting.

Useful checks:

```powershell
./Add-DataCreateLargeSafe.ps1
./Daily-Backup.ps1
./Invoke-AirgapSafeRestore.ps1
./PAS-CreateObjectList.ps1
./PAS-ProcessFailedObjects.ps1
./AutosysRunfile.ps1
./Save-VSCodePackages.ps1
./Install-VSCodePackages.ps1
```

Training aim: practise reliable entry-script behavior, clear failure messages, staged validation and structured evidence while keeping live CyberArk validation separate.
