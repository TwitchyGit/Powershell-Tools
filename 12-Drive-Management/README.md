# Drive management

This section contains drive-mapping training material and a local fixture runner.

## Run order

```powershell
pwsh -NoProfile -NonInteractive -File ./Invoke-SampleDataExample.ps1
pwsh -NoProfile -NonInteractive -File ./Invoke-SampleDataExample.ps1 -View FirstCollection
pwsh -NoProfile -NonInteractive -File ./Invoke-SampleDataExample.ps1 -View AllCollections
```

## Input

The runnable lesson reads `fixtures/sample-data.json`. The fixture contains synthetic drive-shaped records for local
inspection.

`Drive-Mapping.psm1` is module material for the topic. Treat it as code to inspect with the lesson context before using
any pattern against a real Windows host.

## Expected output

The sample runner returns structured objects with:

- `Section`
- `Purpose`
- `CollectionCount`
- `Collections`
- `Collection`, `ItemCount` and `Sample` for collection views

The section does not map drives, contact a file server or validate live Windows drive behavior.

