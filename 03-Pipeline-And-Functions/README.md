# Pipeline and functions

This unit covers reusable command shape: parameters, validation, pipeline input, begin/process/end blocks, output behavior, streams and `ShouldProcess`.

Process focus:

- `BeginProcessEnd.ps1` shows setup, per-item processing and final pipeline summary output.
- `CommandDiscovery.ps1` samples command metadata and parameter discovery.
- `CommentBasedHelp.ps1` inspects local help content and reports whether description and examples exist.
- `DefaultParameterValues.ps1` applies a scoped default, reports selected values and restores prior defaults.
- `ErrorHandling.ps1` converts a non-terminating error into a handled training result.
- `ForEachObjectPipeline.ps1` processes streamed input and reports summary counts.
- `FunctionOutput.ps1` shows clean success output from a function.
- `InformationStream.ps1` separates information messages from success output.
- `ParameterSplatting.ps1` uses a splat and reports the command sample.
- `ParameterValidation.ps1` exposes allowed values for validated input.
- `PipelineFiltering.ps1` reports source, kept and dropped counts.
- `PipelineInputFunction.ps1` returns labelled objects from pipeline input.
- `PreferenceVariables.ps1` changes verbose behavior and restores the previous setting.
- `WhatIfSupport.ps1` returns a changed or previewed result through `ShouldProcess`.

Useful checks:

```powershell
./PipelineInputFunction.ps1
./BeginProcessEnd.ps1
./ParameterValidation.ps1
./WhatIfSupport.ps1
```

Training aim: write functions that behave like normal PowerShell commands, with predictable input, output and error behavior.
