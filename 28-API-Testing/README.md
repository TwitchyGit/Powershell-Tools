# CyberArk PAM API testing

PowerShell 7.6 tools for controlled API validation. This section makes live requests only when explicitly invoked
with `-RunLive`. It is outside the local training course runner. It uses native CyberArk authentication, not SAML,
Windows authentication or psPAS.

## Prerequisites

- Two distinct approved test servers, A and B, each running PowerShell 7.6 or later.
- The same HTTPS PVWA address reachable from both servers with a trusted certificate.
- A dedicated native CyberArk test account permitted to call `GET /PasswordVault/API/Safes?limit=1`.
- Approval to reuse and invalidate this test session. No operational jobs should use this account during the test.
- A working local clipboard on A and an approved secure way to transfer its contents to B.

Use the full PVWA root, for example `https://pvwa.example.test/PasswordVault`. The scripts accept that virtual directory
only. Replace the example hostname with your approved test target. Do not use an IP address to bypass certificate errors.

## Offline check

From this directory:

```powershell
pwsh -NoProfile -NonInteractive -File ./Test-ApiTestingOffline.ps1
```

Input is synthetic credentials, a synthetic token and HTTP response fixtures embedded in the test script. Expected
output is one `Pass` row per case with exit code `0`. Any failed assertion exits `1`. The tests substitute credential
prompts, clipboard operations and web requests. They check logon construction, token reuse, status classification,
cleanup, execution guards and absence of fixture secrets from emitted output. They make no network requests.

## Live token replay and logoff test

1. On Server A, open a dedicated interactive PowerShell session in this directory and run:

   ```powershell
   pwsh -NoProfile -File ./Start-CyberArkSession.ps1 `
       -PvwaUri 'https://pvwa.example.test/PasswordVault' -RunLive -CopyTokenToClipboard
   ```

   Enter the native CyberArk username and password at the credential prompt. The script posts them to
   `/API/Auth/CyberArk/Logon`, obtains the token and establishes a successful Safes read. It then copies the token
   to the clipboard, emits a sanitised baseline result and waits. Leave A waiting while B runs.

2. Transfer the clipboard contents through an approved confidential channel to Server B. Do not use email, chat,
   command-line arguments, repository files or a synced notes application. Disable clipboard history and clipboard
   cloud synchronisation before starting. Remote clipboard forwarding also exposes the token to that session.
   If no approved transfer method is available, stop and clean up A.

3. On Server B, open a dedicated interactive PowerShell session in this directory and run:

   ```powershell
   pwsh -NoProfile -File ./Test-CyberArkTokenReplay.ps1 `
       -PvwaUri 'https://pvwa.example.test/PasswordVault' -RunLive
   ```

   Paste the existing token at the masked prompt. This prompt does not generate a token or authenticate B with a
   password. B sends the token directly as the `Authorization` header, without a `Bearer` prefix. It reads the same
   Safes endpoint, posts `/API/Auth/Logoff`, then repeats the read with the same token.

4. After B finishes, press Enter on A. A attempts logoff as fallback cleanup and clears its clipboard only if it still
   contains this token. An HTTP 401 during A cleanup is accepted as already rejected, which is expected after B
   successfully invalidates the token. Other cleanup failures produce an error and exit `1`.

5. Clear the clipboard and any transfer copies on B. Close the dedicated PowerShell sessions. If either process was
   killed, connectivity failed or cleanup was not confirmed, ask the PAM operator to revoke the session and verify
   it in the approved audit tooling. A `finally` block cannot guarantee cleanup after process termination or power loss.

Expected B result for successful replay followed by rejection:

```text
TestName               : TokenReplayAndLogoff
Result                 : Pass
ReplayHttpStatus       : 200
LogoffHttpStatus       : 200
VerificationHttpStatus : 401
```

A logoff HTTP 204 is also accepted. `Pass` means reuse was observed and the post-logoff request was rejected.
It does not mean token reuse is a desirable security outcome. A succeeds only if its baseline and cleanup complete.

| B observation | Result | Meaning |
|---|---|---|
| Read 200, logoff 200/204, verification 401 | Pass, exit 0 | Reuse observed, then request rejected after logoff |
| Read 200, logoff 200/204, verification 2xx | Fail, exit 1 | Request still accepted after logoff, investigate |
| Initial read rejected | Inconclusive, exit 1 | Reuse not established, check token, permissions and controls |
| Logoff rejected, verification 403/5xx or transport failure | Inconclusive, exit 1 | Invalidation not established |
| HTTP 200 with malformed or unexpected baseline JSON | Inconclusive, exit 1 | Valid Safes response not established |

The baseline permits an empty Safes list, which contains no secret values. Its response must have a JSON `value`
property. Results contain status codes and timings, not Safe names, API response bodies, credentials or tokens.
B attempts fallback logoff if the baseline or primary logoff fails, including when the supplied token was rejected.

## Security and interpretation

- Treat the session token as a credential. Clipboard use deliberately exposes it for this controlled experiment.
  Do not run with screen recording, transcripts, HTTP tracing, debugger inspection or secret-capturing proxies.
- The password must exist briefly as plaintext in memory to form the logon JSON. The token must also exist in memory
  for the HTTP header. Masked input and clearing variables do not guarantee memory erasure. Caught PowerShell error
  records may retain request context in memory. Do not export `$Error` or memory dumps from these sessions.
- Certificate validation stays enabled. Requests have timeouts, no retries and no redirects. Do not add certificate
  bypasses or automatic reauthentication, which would weaken the evidence.
- The Safes call reads metadata only. No account password retrieval, account changes or Safe changes occur. Logon and
  logoff change session state and can produce audit records. A new login may affect existing sessions for this account.
- Use distinct servers and record their identities and observed egress addresses separately. Shared NAT or proxies can
  obscure source differences. A failure on B alone does not establish device or source-IP binding.
- HTTP 401 is evidence that the request was rejected. Correlate with CyberArk and gateway audit records to determine
  the reason and origin. Expiry or an intermediary can also cause rejection. This test does not measure propagation
  delays or prove invalidation across every PVWA node, endpoint or product version.
- `.gitignore` excludes `artifacts/`, `.secrets/`, logs and transcripts in this section. It is not a secret scanner.
  The scripts save no token files. Review `git diff --cached` before any commit and never commit live response dumps.

Local parser and mocked checks do not prove Windows clipboard behaviour, network reachability, live authentication,
token portability or CyberArk session invalidation. Those require the two-server live run. Use the result object as
evidence for this session and target only. No live CyberArk testing is performed by the offline command.

## Suite roadmap

| Next tool | Intended evidence | Boundary |
|---|---|---|
| Permission boundaries | Allowed and denied test resource reads against an explicit access matrix | Dedicated test Safes and accounts |
| Pagination completeness | All expected IDs retrieved, no missing pages or duplicate IDs | Known synthetic inventory |
| HTTP failure handling | Correct classification, bounded retries and redacted diagnostics | Offline fixtures first |
| Session expiry | Idle expiry measured separately from a session kept active | Dedicated sessions and agreed duration |
| Missing and invalid tokens | Protected endpoints reject a small fixed set of unauthenticated requests | No guessing real tokens |
| TLS and availability | Trusted connection and bounded read latency | No certificate bypass or load generation |
| Audit correlation | Test timestamps and actions matched to approved audit exports | Authorised audit access |

Concurrent sessions, rate limits, failed-login lockout, write permissions and dummy-secret retrieval need separate
scopes, dedicated resources and agreed stop conditions. These tools are planned, not implemented here.

## API references

- [CyberArk native logon](https://docs.cyberark.com/pam-self-hosted/latest/en/content/webservices/logon.htm)
- [CyberArk logoff](https://docs.cyberark.com/pam-self-hosted/latest/en/content/webservices/logoff.htm)
- [CyberArk Safe Management example](https://github.com/cyberark/epv-api-scripts/blob/main/Safe%20Management/Safe-Management.ps1)

Confirm endpoint behaviour against the documentation for your installed PAM version before the live run.
