# CyberArk 14.2 User/Safe regression suite

This is the User/Safe regression suite containing 21 integration tests. It is not a unit
test because it signs in to a live PVWA and exercises live Vault APIs.

The separate administrator regression suite is documented in `README-Admin.md`.
Run both unchanged before and after a CyberArk upgrade to compare the same API
contracts from end-user and administrator perspectives.

## Coverage

- CyberArk or LDAP REST authentication and current-user lookup
- Local Vault user create, read, update and delete
- Safe create, read, update and delete
- Safe-member create, read, permission update and delete
- Generated end-user login using a password held in memory only
- Account create, list, read, secret retrieval, update and delete as that user
- Confirmation that account-only permissions do not allow Safe administration
- Verification after each write
- Best-effort cleanup and logoff even when a test fails
- Console tracing of every API method and relative route, without headers or bodies
- NUnit XML output for upgrade/change comparisons

The suite only creates and deletes uniquely named objects beginning with the
configured `TestObjectPrefix`. It does not update or delete an existing user,
Safe, Safe member or account. The test account uses a reserved `.invalid`
address and has automatic CPM management disabled so the Vault does not contact
a real endpoint.

## Prerequisites

- Windows PowerShell 5.1 or PowerShell 7
- Pester 5.2 or later
- Network access to PVWA using a trusted HTTPS certificate
- An administrator with the Vault authorisations required to add/update users
  and add Safes. The logged-on administrator becomes an owner of each Safe it
  creates, allowing it to manage that Safe and its members.
- A CPM user matching the configured `ManagingCPM` value. The default is
  `PasswordManager`.
- An active password platform matching `TestPlatformId`. The default is
  `WinServerLocal`, but platform IDs are environment-specific.

## Configure

Open `ConfigModule.psm1`. It is the single source of truth for every editable
environment value and test default. At minimum, replace:

```powershell
PVWAUrl = 'https://pvwa.example.com/PasswordVault'
```

If the environment uses a differently named CPM, also change `ManagingCPM`.
Confirm that `TestPlatformId` identifies an active password platform which can
accept `address` and `userName`. Keep `TestObjectPrefix` at eight characters or
fewer.

Do not put administrator credentials, generated passwords, session tokens or
object IDs in `ConfigModule.psm1`. Those values are created for one run and are
held only in local runtime state.

The suite deliberately has no option to disable TLS certificate validation.

## Run

From this directory:

```powershell
.\Invoke-CyberArk14.2Regression.ps1
```

The runner asks for the administrator user name once, then asks for its password
as a secure string. It does not save either value. Results are written to a new
timestamped XML file under `TestResults`.

Run this in a non-production or approved test Vault first. Although the suite
limits deletion to its own generated objects, it intentionally performs live
create, update and delete operations.

## Interpreting the result

A process exit code of `0` means all 21 tests passed. An exit code of `1` means
one or more operations failed. Pester's console output and timestamped NUnit XML
show the specific API operation and HTTP status. A successful trace resembles:

```text
[API] RUN  POST   /API/Users
[API] PASS POST   /API/Users (284 ms)
[API] RUN  PATCH  /API/Accounts/24_42
[API] PASS PATCH  /API/Accounts/24_42 (193 ms)
```

The trace deliberately excludes authentication headers, request bodies and
response bodies because they can contain credentials or account secrets.

Static parsing of these scripts cannot prove the APIs work in a particular
CyberArk environment. Establish a successful 14.2 baseline before an upgrade,
then run the same unchanged files after the upgrade and compare results.
