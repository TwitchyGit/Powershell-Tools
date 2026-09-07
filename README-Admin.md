# CyberArk 14.2 administrator regression suite

This is a separate Pester integration suite for REST operations commonly used
by a CyberArk administrator. It complements the User/Safe suite rather than
duplicating its user, Safe, Safe-member and account lifecycle tests.

## Coverage

- CyberArk or LDAP logon, current-user validation and logoff
- PVWA server information and configured authentication-method inventory
- component monitoring summary and selected component details
- user, Vault group, Safe and account collection access
- platform summary, target-platform and configured-platform reads
- PSM connection-component and server inventory
- optional LDAP directory and live PSM session inventory
- disposable local user create and delete
- disposable Vault group create, read, rename and delete
- disposable Vault group member add, verify and remove
- disposable AAM application create, read and delete
- disposable AAM machine-address authentication create, read and delete
- explicit API method, relative route, result and elapsed-time console output
- NUnit XML output suitable for pre-upgrade and post-upgrade comparison

The suite does not edit or delete an existing object. Every write uses an object
name derived from `TestObjectPrefix` plus a random run suffix. Cleanup uses only
IDs returned by those create calls.

## Configure

Edit `ConfigModule.psm1`, which is shared with the User/Safe suite. At minimum,
set `PVWAUrl` and confirm `TestPlatformId`. The following administrator switches
control installed or permission-sensitive features:

```powershell
TestSystemHealth          = $true
TestPSMConnectorInventory = $true
TestAAMApplicationCrud    = $true
TestLDAPDirectoryInventory = $false
TestLiveSessionInventory   = $false
```

Disable an enabled check when its component is not installed or the test
administrator is intentionally not authorised to use it. Enable LDAP or live
session inventory only where those features and permissions exist. Adjust
`ComponentDetailIds` to match installed components. Keeping a stable set of
enabled tests is important when results are compared across releases.

## Run

From this directory:

```powershell
.\Invoke-CyberArk14.2AdminRegression.ps1
```

The runner asks for the administrator user name once, then its password as a
secure string. It writes a timestamped NUnit XML file under `TestResults` and
returns exit code `0` when every enabled test passes or `1` when any test fails.

Example route trace:

```text
Suite: CyberArk 14.2 Administrator Regression
[API] RUN  GET    /api/server
[API] PASS GET    /api/server (118 ms)
[API] RUN  POST   /API/UserGroups
[API] PASS POST   /API/UserGroups (271 ms)
[API] RUN  PUT    /API/UserGroups/42
[API] PASS PUT    /API/UserGroups/42 (190 ms)
[API] RUN  DELETE /API/UserGroups/42
[API] PASS DELETE /API/UserGroups/42 (166 ms)
```

Headers, request bodies and response bodies are never printed by the trace.

If one route fails, the method and route remain visible beside the HTTP result:

```text
[API] RUN  GET    /API/Platforms/WinServerLocal/
[API] FAIL GET    /API/Platforms/WinServerLocal/ (HTTP 403; 104 ms)
  [-] reads the configured account platform 126ms
      CyberArk REST GET /API/Platforms/WinServerLocal/ failed with HTTP 403

Tests completed in 8.91s
Tests Passed: 26, Failed: 1, Skipped: 2
```

## Baseline use

Run both suites successfully against 14.2 and retain their XML results. After an
upgrade, run the exact same scripts with the same configuration. A route failure,
response-schema assertion failure, changed authorisation result or skipped test
then becomes visible in the console and XML comparison.

Static parsing proves only that PowerShell can parse the files. It does not prove
the routes, permissions or configured components work in a particular Vault.
First run this suite in a non-production or specifically approved test Vault.

Operations intentionally left out are recorded in `ADMIN-EXCLUSIONS.md`.
