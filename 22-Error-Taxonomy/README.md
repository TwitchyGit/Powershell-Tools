# Error taxonomy

This section shows how to classify failures before choosing whether to stop, continue or retry.

Run:

```powershell
./Invoke-ErrorTaxonomyLesson.ps1
./Invoke-ErrorTaxonomyLesson.ps1 -View Retry
```

The lesson reads `fixtures/sample-data.json` and demonstrates:

- terminating error decisions
- non-terminating item failures
- native command exit handling
- retryable and permanent failures
- one final entry-script exit decision

The script does not call native tools or services.
