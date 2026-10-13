# CHANGE01 - Production security hardening for File-Handler.psm1

## Purpose

`File-Handler.psm1` is an elevated Windows Restart Manager helper used to identify and stop processes or services that hold files open under a directory. Before using the stop function on a production system, the module needs tighter controls around target scope, service stopping, incomplete scans and module integrity.

The aim is to reduce the risk of accidental production outage, false clean results and elevated-code tampering.

## Required changes

### 1. Restrict destructive scope to approved deployment roots

`Stop-DirectoryLockProcess` currently accepts any path on the configured allowed drive. The default drive guard blocks paths outside `D:`, but it still allows broad locations such as application roots, shared data roots or unrelated service folders on that drive.

Add a stricter root allowlist before any process or service stop is attempted.

Required behaviour:

- Accept one or more approved deployment roots.
- Resolve the requested path to a full canonical path.
- Confirm the resolved path is below one approved root.
- Refuse drive roots, share roots and any path outside the approved deployment roots.
- Return a clear terminating error before calling `Get-DirectoryLockProcess` when the path is out of scope.

Suggested implementation shape:

- Add an `AllowedRoot` or `AllowedRoots` parameter to `Stop-DirectoryLockProcess`.
- Keep `AllowedDrive` only if it still adds value after root validation.
- Compare normalized full paths, not raw input strings.
- Treat failed resolution as a stop condition.

### 2. Add process and service allowlists for stop actions

The module currently skips core Windows process names and Restart Manager critical applications, but it can still stop any non-protected application or reported service under the target directory.

Add explicit allowlists for destructive actions.

Required behaviour:

- Only stop process names that match an approved list.
- Only stop service names that match an approved list.
- Default to skip when no allowlist match exists.
- Include the skip reason in the output object.
- Preserve the existing PID start-time check for process stops.

Suggested implementation shape:

- Add `AllowedProcessName` and `AllowedServiceName` parameters.
- Make the stop decision require both the existing safety checks and an allowlist match.
- Keep allowlist matching case-insensitive.
- Avoid wildcard matching unless the caller explicitly opts into it.

### 3. Make incomplete file enumeration visible and fail closed by default

`Get-DirectoryLockProcess` currently enumerates files with `Get-ChildItem -ErrorAction SilentlyContinue`. Access denied, long path, transient I/O and other enumeration failures can be hidden. That can produce a false result where no holders are reported because part of the tree was never checked.

Change enumeration so failures are captured and reported.

Required behaviour:

- Capture enumeration errors.
- Return or emit the failed paths and error messages.
- Fail by default when enumeration is incomplete.
- Provide an explicit opt-in switch only if partial scans are operationally needed.
- Ensure `Stop-DirectoryLockProcess` does not stop anything after an incomplete scan unless the caller deliberately allowed partial results.

Suggested implementation shape:

- Use `-ErrorVariable` with `Get-ChildItem`.
- Add an `AllowPartialScan` switch if needed.
- Add `ScanComplete` or equivalent metadata to results if non-terminating partial scans are supported.

### 4. Verify service stop outcome before reporting success

The service path uses `Stop-Service -Force` and immediately reports `Stopped`. That can hide services left in `StopPending`, active services that refused to stop or dependency effects caused by forceful stopping.

Add post-stop verification for services.

Required behaviour:

- Check service state after `Stop-Service`.
- Wait up to `TimeoutSeconds`.
- Report `Stopped` only when the final state is confirmed as stopped.
- Report `Failed` when the service remains running, cannot be queried or stays pending after timeout.
- Include dependency information or a clear warning when dependent services may be affected.

Suggested implementation shape:

- Use `Get-Service -Name $Locker.ServiceName` before and after stop.
- Avoid `-Force` by default.
- Add an explicit `ForceServiceStop` switch if force is still required.
- Poll status until stopped or timeout.

### 5. Keep destructive execution opt-in

The module supports `ShouldProcess`, so `-WhatIf` works. Production use should make preview-first operation the expected path.

Required behaviour:

- Document production use as a two-step operation: discovery or `-WhatIf` first, destructive run second.
- Ensure any wrapper or deployment script calls preview mode before stopping.
- Ensure skipped, failed and stopped holders are all visible in output.

Suggested implementation shape:

- Do not hide stop output behind information messages only.
- Keep structured output suitable for deployment logs.
- Consider adding a wrapper-level `ConfirmStop` switch if this module is called from automation.

### 6. Protect the module file and load path

The module compiles inline C# with `Add-Type` and is intended to run elevated. If the file or containing folder is writable by non-admin users, tampering with the module becomes elevated code execution.

Required behaviour:

- Store the module in a locked-down production path.
- Ensure only administrators or the deployment service account can modify the module.
- Avoid loading the production module directly from a user-writable sync folder.
- Use code signing where the environment supports it.

Suggested implementation shape:

- Add deployment guidance for module ACLs.
- Add a release packaging step that copies the module to a controlled production module path.
- Optionally enforce `Get-AuthenticodeSignature` in the production wrapper before import.

## Validation required

Static checks:

- Parse `File-Handler.psm1` with PowerShell and confirm zero parser errors.
- Check brace, parenthesis and bracket balance for touched PowerShell files.
- Confirm all new PowerShell code follows the shared style rules.

Windows functional checks:

- Run `Get-DirectoryLockProcess` against a test directory with a known file lock.
- Run with a path outside the approved root and confirm it refuses before scanning.
- Run with an incomplete-access test tree and confirm it fails closed by default.
- Run `Stop-DirectoryLockProcess -WhatIf` and confirm no holder is stopped.
- Run stop tests against a non-critical test process and confirm PID start-time validation remains in place.
- Run service-stop tests only against a disposable test service.

Production readiness checks:

- Confirm the production module path is not writable by ordinary users.
- Confirm logs capture stopped, skipped and failed holders.
- Confirm automation treats any failed or incomplete result as a deployment stop condition.

## Out of scope

This change does not need to replace Restart Manager, add external tools such as `handle.exe` or implement live production testing against business services. Live validation should use disposable processes and services first, then a controlled maintenance-window test if production use is approved.
