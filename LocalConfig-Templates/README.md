# LocalConfig templates

`ConfigModule.psm1` reads `Environment.cfg` and `ServiceOwner.cfg` from
`${BaseLocalConfig}` (`D:\Reports-LocalConfig` on the deployment server) and
returns `$false` if either file is missing. `Vault.ini` is referenced by
`$ConfVaultFile` but not read directly by the module itself.

These three files cannot be created at their real path from this repo (that
path only exists on the Windows server the scripts run on). Copy them to
`D:\Reports-LocalConfig\` there, then edit the values for the target server:

- `Environment.cfg` - contains exactly one of `PROD` or `DEV`.
- `ServiceOwner.cfg` - contains the service account name the scripts run as.
- `Vault.ini` - CyberArk vault connection settings for this server.
