# Expected outputs

This file defines the expected evidence shape for the course. Exact timestamps, temporary paths and generated identifiers can vary between runs.

## Course checks

`05-Modules-And-Configuration/Check.ps1` should emit one object with:

- `CheckedFiles`: count of parsed `.ps1`, `.psm1` and `.psd1` files.
- `ParserErrors`: `0` for success.
- `ModulesLoaded`: `True` for success.

`Invoke-CourseSmokeTest.ps1` should emit one object per script and a final summary object. Each script result should include:

- `Script`: relative script path.
- `ExitCode`: native process exit code.
- `Passed`: Boolean result.
- `DurationMs`: elapsed runtime in milliseconds.

## Unit evidence

- Unit 01 returns small objects that demonstrate values, operators, loops or version-specific syntax.
- Unit 02 returns objects that demonstrate property selection, grouping, conversion or parsed structured data.
- Unit 03 returns objects that demonstrate pipeline input, streams, validation, errors or command metadata.
- Unit 04 returns objects that demonstrate file state, environment state, process state, REST-shaped data or native exit code evidence.
- Unit 05 returns objects that demonstrate module import, configuration loading and static validation.
- Unit 06 returns deployment-shaped manifests, preflight records and receipts.
- Unit 07 returns directory-service-shaped account, group or computer records from local data.
- Unit 08 returns backup, restore, AutoSys, package, compatibility or CyberArk-shaped records from local data.
- Credential Management returns redacted credential metadata, decision records and validation-boundary statements.

## Failure evidence

A controlled failure should include a clear error message and process exit code `1`. Entry scripts should not return exit codes other than `0` or `1`.

