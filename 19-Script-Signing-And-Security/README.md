# Script signing and security

This section shows how script-signing results and execution-policy settings affect a local training decision.

Run:

```powershell
./Invoke-SigningSecurityLesson.ps1
./Invoke-SigningSecurityLesson.ps1 -View Policy
```

The lesson reads `fixtures/sample-data.json` and demonstrates:

- valid, missing and changed signatures
- trusted publisher matching
- the limit of execution policy as a safety control
- why hash and publisher checks are separate decisions

The script does not read certificate stores, change execution policy, sign files or run untrusted scripts.
