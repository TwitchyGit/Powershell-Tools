# PowerShell course syllabus

This course teaches practical PowerShell by moving from small language examples to operational scripts. The examples use local sample data so learners can inspect behavior without access to AD, CyberArk, AutoSys, Git remotes or Windows hosts.

## Learning outcomes

By the end of the course a learner should be able to:

- Explain how PowerShell passes objects through commands.
- Build scripts with explicit parameters, predictable output and controlled errors.
- Read and write CSV, JSON, XML and PowerShell data files.
- Separate configuration, helper functions and entry scripts.
- Produce operational evidence such as receipts, manifests and summary objects.
- State which checks are local static checks and which require live systems.

## Unit sequence

1. `01-Language-Fundamentals`: syntax, values, control flow, jobs and version-specific operators.
2. `02-Objects-And-Data`: object shape, hashtables, calculated properties, CSV, JSON, XML and PSD1 parsing.
3. `03-Pipeline-And-Functions`: pipeline behavior, functions, streams, validation, errors and `ShouldProcess`.
4. `04-Files-Environment-And-Runtime`: files, paths, environment values, native commands, REST shape and local secret handling.
5. `05-Modules-And-Configuration`: shared functions, module imports, data files and course static checks.
6. `06-Deployment-And-Git-Training`: local deployment staging, manifests, receipts and Git-shaped control points.
7. `07-Operations-And-Directory-Services`: AD-shaped account, group and computer checks using local records.
8. `08-Backup-And-Compatibility`: backup, restore, AutoSys, CyberArk-shaped records, package handling and compatibility checks.

## Assessment points

- Unit 01: learner explains output type and version requirement for three scripts.
- Unit 02: learner adds one property to a fixture and updates filtering or grouping logic.
- Unit 03: learner creates one function that accepts pipeline input and emits objects.
- Unit 04: learner proves a native command exit code and logs the evidence.
- Unit 05: learner imports a module, reads PSD1 configuration and runs the static check.
- Unit 06: learner creates a deployment receipt from local package data.
- Unit 07: learner classifies AD-shaped records without using live AD.
- Unit 08: learner builds backup or restore evidence from local fixtures.
- Credential Management: learner selects a safe credential pattern and states the live-validation boundary.

## Capstone

The capstone combines configuration, object processing, operational records and validation. Learners should create a script that reads a fixture, applies validation, writes a receipt, returns structured output and exits `0` for success or `1` for failure.

## Validation boundary

`Check.ps1` and `Invoke-CourseSmokeTest.ps1` provide local static and smoke-test evidence. They do not prove live AD, PVWA, AutoSys, Windows PowerShell 5.1 or network behavior.

