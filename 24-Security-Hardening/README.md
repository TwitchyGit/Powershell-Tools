# Security hardening

This section shows how to turn common script risks into specific hardening actions.

Run:

```powershell
./Invoke-SecurityHardeningLesson.ps1
./Invoke-SecurityHardeningLesson.ps1 -View Redacted
```

The lesson reads `fixtures/sample-data.json` and demonstrates:

- secret redaction
- least-privilege checks
- safe temp-file handling
- certificate validation boundaries
- safe diagnostic output

The script does not change policy, permissions, certificate validation or files outside the lesson folder.
