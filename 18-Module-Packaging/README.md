# Module packaging

This section shows how a PowerShell module is described before it is packaged or published.

Run:

```powershell
./Invoke-ModulePackagingLesson.ps1
./Invoke-ModulePackagingLesson.ps1 -View Exports
./Invoke-ModulePackagingLesson.ps1 -View Layout
```

The lesson reads `fixtures/sample-data.json` and demonstrates:

- manifest fields that describe a module
- public functions that belong in `FunctionsToExport`
- private helpers that should stay behind the module boundary
- the package file layout expected by a reusable module

The script does not import, install, publish or modify a module.
