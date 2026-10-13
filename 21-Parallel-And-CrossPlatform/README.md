# Parallel and cross-platform execution

This section shows how to plan parallel work without hiding ordering or platform risks.

Run:

```powershell
./Invoke-ParallelCrossPlatformLesson.ps1
./Invoke-ParallelCrossPlatformLesson.ps1 -View Platform
```

The lesson reads `fixtures/sample-data.json` and demonstrates:

- throttle grouping
- shared-state hazards
- ordered output planning
- Windows-only boundaries
- portable PowerShell 7 task shapes

The script does not start jobs, create runspaces, invoke remote commands or touch Windows-only providers.
