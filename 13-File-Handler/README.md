# File handler

This section contains file-handler training material and a local fixture runner.

## Run order

```powershell
pwsh -NoProfile -NonInteractive -File ./Invoke-SampleDataExample.ps1
pwsh -NoProfile -NonInteractive -File ./Invoke-SampleDataExample.ps1 -View FirstCollection
pwsh -NoProfile -NonInteractive -File ./Invoke-SampleDataExample.ps1 -View AllCollections
```

## Input

The runnable lesson reads `fixtures/sample-data.json`. The fixture contains synthetic file-handler records for local
inspection.

`File-Handler.psm1` is module material for the topic. Treat it as code to inspect with the lesson context before using
any pattern against real locked files or Windows services.

## Expected output

The sample runner returns structured objects with:

- `Section`
- `Purpose`
- `CollectionCount`
- `Collections`
- `Collection`, `ItemCount` and `Sample` for collection views

The section does not stop services, query Restart Manager or prove live Windows file-lock behavior.

