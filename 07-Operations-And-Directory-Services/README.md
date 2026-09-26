# Operations and directory services

This unit uses AD-shaped examples for account checks, computer scans, group membership and input styles.

Process focus:

- `ADAccountsMonitor.ps1` classifies local sample computers as ready, disabled or stale.
- `Scan-ADComputerOU.ps1` validates an OU-shaped search base and returns scan counts.
- `CheckADAccount.ps1` models enabled, expired and locked account states from local sample data.
- `AddGroup-Member.ps1` records an idempotent group-membership training action.
- `LDAP-Win-Query.ps1` builds an escaped LDAP filter and marks paged-result intent.
- `Check-User-CLI.ps1` and `Check-User-GUI.ps1` show different input surfaces with shared validation shape.

Useful checks:

```powershell
./ADAccountsMonitor.ps1
./Scan-ADComputerOU.ps1
./Check-User-CLI.ps1
./CheckADAccount.ps1
./LDAP-Win-Query.ps1
```

Training aim: practise operational script shape without treating sample data as live AD validation.
