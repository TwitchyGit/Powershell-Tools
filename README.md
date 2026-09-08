# Cyb-User-Onboarding

PowerShell tools for CyberArk account, Safe and user reporting plus supporting Active Directory checks.

This README describes the active code in the project root and `Config` directory. Files under `Archive`
are retained as reference copies and are not used by the active account-reporting path.

## Active account-reporting files

| File | Responsibility |
|---|---|
| `Scan-AllObjectsInSafes.ps1` | Command-line entry point. Loads configuration, authenticates to PVWA and runs the selected reports. |
| `Config/ConfigModule.psm1` | Defines environment paths, PVWA settings, output locations and mutable runtime configuration. |
| `Config/PSFunctions.psm1` | Implements authentication, retries, Safe discovery, account retrieval, CSV creation and logging. |
| `ReportAccounts-Spec.md` | Detailed behaviour specification for the `-ReportAccounts` path. |

## Running the accounts report

Run from Windows PowerShell 5.1 on the reporting server:

```powershell
.\Scan-AllObjectsInSafes.ps1 -ReportAccounts
```

The request timeout defaults to 300 seconds. It can be changed for the run:

```powershell
.\Scan-AllObjectsInSafes.ps1 -ReportAccounts -ConnectionTimeoutSeconds 600
```

The launcher can also run the account, user and Safe reports in one process:

```powershell
.\Scan-AllObjectsInSafes.ps1 -ReportAccounts -ReportUsers -ReportSafes
```

`ConfPVWAURL` comes from configuration. The PVWA URL is not supplied as a command-line parameter.

## Required configuration

The current configuration expects these server-side files and paths:

| Setting or file | Current purpose |
|---|---|
| `D:\Reports-LocalConfig\Environment.cfg` | Must contain `PROD` or `DEV`. |
| `D:\Reports-LocalConfig\ServiceOwner.cfg` | Identifies the configured service owner. |
| `D:\Reports-LocalConfig\cs_Report_Accounts.ini` | PowerShell CLIXML credential used for the accounts report. |
| `C:\Scripts\Config\Configuration.psm1` | Legacy shared configuration module imported by the launcher. |
| `$ConfPVWAURL` | Environment-specific PVWA base URL. |
| `$ConfDirLogs` | Directory that receives the CSV report. It must already exist and be writable. |

The account credential file must deserialize to a `PSCredential` containing a username and password.

## Exact `-ReportAccounts` flow

### 1. Load modules and configuration

The launcher imports `ConfigModule.psm1`, `PSFunctions.psm1` and the configured legacy module. It stops with
exit code `1` if module loading fails, the environment is blank or `ConfPVWAURL` is blank.

The PVWA base URL has trailing slashes removed once. The launcher then constructs the authentication,
accounts, users and Safes API URLs from the suffixes in `ConfigModule.psm1`.

### 2. Configure logging and runtime state

The launcher passes the credential path, request timeout, API URLs, log directory, normalized PVWA URL and
Autosys state into the function module. Autosys runs suppress interactive progress output.

Logging writes to the console and to `$ConfLogFile` when that file is configured. Debug output includes the
resolved API URLs when `-Debug` is supplied.

### 3. Authenticate before running reports

`Get-AuthToken` reads the CLIXML credential and posts JSON containing `username` and `password` to the PVWA
CyberArk Logon endpoint. The returned token has JSON quote characters removed and is cached in
`$ConfOnboardingRuntime.AuthTrimmed`.

Normal authentication uses the standard retry policy described below. If this initial authentication fails,
the launcher exits immediately with code `1` before any selected report runs.

### 4. Prepare the CSV output

`Process-AccountsReport` sets the output file to:

```text
$ConfDirLogs\Data_PasswordObjects_Bulk.csv
```

It checks that the output directory exists. It then proves write access by writing temporary content to the
target path and deleting it. `Get-AllAccounts` recreates the file with the fixed CSV header, so an existing
report at that path is overwritten.

### 5. Retrieve the Safe list

`Get-AllSafes` requests the Safes API in pages of 100 using `offset` and `limit`.

- A successful short page is treated as the final page.
- An empty response ends pagination.
- A failed page is logged, counted and skipped by advancing the offset.
- Three consecutive failed Safe-list pages stop Safe-list retrieval.
- The final Safe-list failure summary reports a count only.

If no Safes are returned, `Get-AllAccounts` writes a zero-row CSV header, logs that accounts cannot be
enumerated and returns with `AccountsResult = 0`. The current code does not throw for this condition.

### 6. Exclude system Safes

Before requesting any accounts, the code excludes Safe names matching:

```text
CPM*
Log*
Notification*
Pictures
PSM*
PVWA*
System*
VaultInternal*
```

Matching is case-insensitive under normal PowerShell `-like` behaviour. Only the number of excluded Safes
is logged. Their names are not printed.

### 7. Process eligible Safes sequentially

Eligible Safes are processed one at a time. The active path has no threading, runspaces or parallel account
requests.

For each Safe the function:

1. URL-encodes the Safe name.
2. Requests `API/Accounts` with a `safeName` filter and page limit of 1000.
3. Converts each successful JSON page into CSV rows.
4. Follows `nextLink` until no further page is supplied.
5. Accepts only same-host HTTP or HTTPS absolute links. Relative links are resolved against the configured
   PVWA base URL.
6. Buffers all valid rows for that Safe in memory.
7. Writes the buffered rows once when the Safe completes or immediately after that Safe fails.

The same persistent HTTP connection can be reused across sequential requests. The code does not force
`Connection: close`.

### 8. Handle account, page and Safe failures

If one account cannot be converted into a row, that account is skipped. Its Safe name, account ID and error
are logged. Other accounts in the same page continue processing.

If the first account page for a Safe fails, the Safe is classified as `FailedSafe`. If one or more pages
were already retrieved, it is classified as `PartialSafe` and the rows already collected are retained.

The final entry for each failed or partial Safe includes:

```text
name=<Safe name> id=<Safe ID> error=<error message>
```

An individual Safe failure does not change the process exit code.

### 9. Confirm PVWA availability after three transient Safe failures

After three consecutive Safes fail with transient connection-type errors, the script performs one fresh
PVWA login attempt:

- The login check uses exactly one HTTP attempt with no retry.
- If login succeeds, the new token is cached, the consecutive-failure counter resets and account retrieval
  continues with the next Safe.
- If login fails, account retrieval stops. Attempted failed or partial Safes are printed with their errors.
  Remaining unattempted Safes are reported only as `SkippedPVWAUnavailable: N safe(s)`.
- After writing those summaries, `Get-AllAccounts` throws. The accounts report fails and the launcher sets
  the final process exit code to `1`.

A successful Safe also resets the consecutive transient-failure counter. Permanent failures and JSON parse
failures do not advance that counter.

### 10. Finish the run

`Get-AllAccounts` stores the number of written account rows in `$ConfOnboardingRuntime.AccountsResult`.
The launcher can continue with `-ReportUsers` or `-ReportSafes` if those switches were also supplied. Any
report failure makes the final process exit code `1`.

`Cleanup` performs .NET garbage collection. The current launcher does not call a PVWA logoff endpoint.

## REST retry policy

Normal PVWA calls use up to three attempts. After the first transient failure the script waits 10 seconds.
After the second it waits 20 seconds. The one-attempt PVWA availability login is the only exception.

| Classification | Current handling |
|---|---|
| HTTP `401` | Transient. For authorised requests, refresh the token before the next attempt. |
| HTTP `429`, `500`, `502`, `503`, `504` | Transient and retried. |
| HTTP `400`, `403`, `404` | Permanent and not retried. |
| Timeout, connection closed/reset/refused, DNS failure or recognised network exception | Transient and retried. |
| Unrecognised error | Not transient and fails immediately. |

Once attempts are exhausted, the REST helper throws an exception marked with `PVWATransient = true`. The
Safe loop uses that marker when counting consecutive transient Safe failures.

## CSV output schema

The report always uses these 25 columns in this order:

| Column | Current source or value |
|---|---|
| `rowid` | `Account.id` |
| `AccountName` | `Account.name` |
| `Address` | `Account.address` |
| `UserName` | `Account.userName` |
| `Platform` | `Account.platformId` |
| `ModificationDate` | Converted `secretManagement.lastModifiedTime` |
| `ModifiedBy` | Blank |
| `LastUsedDate` | Blank |
| `LastUsedBy` | Blank |
| `Safe` | `Account.safeName` |
| `CreatedBy` | Blank |
| `CreationDate` | Converted `Account.createdTime` |
| `CPMStatus` | `secretManagement.status`, otherwise `NotSet` |
| `Folder` | Blank |
| `LastTask` | Blank |
| `CPMErrorDetails` | `secretManagement.manualManagementReason`, otherwise `NotSet` |
| `CPMDisabled` | `secretManagement.automaticManagementEnabled`, otherwise `NotSet` |
| `LastFailDate` | Blank |
| `LastSuccessVerification` | Converted `secretManagement.lastVerifiedTime` |
| `DateTimeNow` | Blank |
| `ResetImmediately` | Blank |
| `ApplicationID` | `platformAccountProperties.ApplicationID`, otherwise `NotSet` |
| `ConfigItemType` | `platformAccountProperties.ConfigItemType`, otherwise `NotSet` |
| `LastReconciledTime` | Converted `secretManagement.lastReconciledTime` |
| `PlatformAccountProperties` | Blank |

Despite the column name, `CPMDisabled` receives `automaticManagementEnabled` directly. The current code does
not invert that boolean.

Converted dates use `dd/MM/yyyy HH:mm`. `ConvertDate` checks the input object's `.Length`; a value with a
length above 10 is divided by 1,000,000 before conversion. Other values are treated as Unix seconds. A
numeric PowerShell scalar normally has `.Length = 1`, so the division branch is reliably selected only when
the timestamp arrives as a long string or another object whose `.Length` reflects its digits.

Every CSV value is enclosed in double quotes. Embedded double quotes are doubled before the fields are
joined with commas.

## End-of-run account summary

The account scan logs:

- Total accounts written.
- Attempted Safe count and eligible Safe count.
- `FailedSafe` entries with name, ID and error.
- `PartialSafe` entries with name, ID and error.
- `SkippedAccounts` entries for individual account conversion failures.
- `SafeListingFailedPages` as a count.
- Configured system-Safe exclusions as a count only.
- `SkippedPVWAUnavailable` as a count only.

If none of the failure categories occurred, the script logs `No failures during account retrieval.`

## Exit-code behaviour

| Condition | Exit code |
|---|---:|
| Successful selected reports | `0` |
| Initial module, environment, URL or authentication failure | `1` |
| Output directory or output write-access failure | `1` |
| Failed one-attempt PVWA availability login | `1` |
| Individual failed or partial Safe while PVWA remains responsive | Does not change the exit code |
| Individual malformed account row | Does not change the exit code |

If no report switch is supplied, the current launcher still loads configuration and authenticates before
running cleanup and returning `0`, assuming startup succeeds.

## Current TLS and certificate behaviour

The active code explicitly selects TLS 1.2. It disables certificate revocation checking. `ConfigModule.psm1`
also installs a certificate-validation callback that accepts the server certificate, including self-signed
or expired certificates. This section records the current implementation and is not a security endorsement.

## Validation status

The account flow has passed static PowerShell parsing, delimiter-balance checks and mocked flow tests for:

- Successful sequential account retrieval.
- Partial Safe retention.
- Standard retries.
- Safe-list page failures.
- Successful recovery after the one-attempt PVWA login check.
- Failed login with detailed attempted-Safe errors and count-only skipped Safes.

It has not been validated against a live PVWA from this development environment.

For the design-level contract and implementation history, see [ReportAccounts-Spec.md](ReportAccounts-Spec.md).
