# Troubleshooting

This section shows how to collect reproducible evidence before changing code or environment settings.

Run:

```powershell
./Invoke-TroubleshootingLesson.ps1
./Invoke-TroubleshootingLesson.ps1 -View Bundle
```

The lesson reads `fixtures/sample-data.json` and demonstrates:

- symptom to layer mapping
- useful first questions
- diagnostic bundle content
- safe share decisions
- keeping evidence separate from guesses

The script does not run `Trace-Command`, query event logs or inspect the operating system.
