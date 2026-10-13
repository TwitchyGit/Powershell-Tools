# REST and HTTP resilience

This section shows how REST clients should classify response problems before retrying or parsing.

Run:

```powershell
./Invoke-RestResilienceLesson.ps1
./Invoke-RestResilienceLesson.ps1 -View RetryPlan
```

The lesson reads `fixtures/sample-data.json` and demonstrates:

- pagination-shaped success data
- token expiry decisions
- throttling and `Retry-After` style delays
- malformed JSON detection
- content-type checks before parsing
- sanitized diagnostics that avoid logging response bodies

The script does not call a network endpoint or use a real bearer token.
