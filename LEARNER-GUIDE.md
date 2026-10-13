# Learner guide

Use this guide to choose what to run in each numbered section and what result shape to expect.

All examples use local files or local synthetic objects unless a section README explicitly says otherwise. Treat output
as training evidence. Do not treat it as live Windows, Active Directory, WinRM, CyberArk, AutoSys or Git validation.

## Common pattern

Run scripts from their section folder or pass the full path to `pwsh -File`.

```powershell
pwsh -NoProfile -NonInteractive -File './Section-Folder/Script.ps1'
```

Most scripts return objects to the success stream. View the object properties directly or pipe to `Format-Table` when
you only need display output.

```powershell
$Result = pwsh -NoProfile -NonInteractive -File './20-Rest-And-Http-Resilience/Invoke-RestResilienceLesson.ps1'
```

Fixture-backed sections read `fixtures/sample-data.json`. Change that fixture to test another safe training scenario.

## Section interaction guide

### `01-Language-Fundamentals`

- Run: individual scripts such as `ArrayIndexing.ps1`, `SwitchStatement.ps1` and `StrictMode.ps1`.
- Input: built-in sample arrays, strings, dates and counters.
- Output: values or objects showing syntax behavior, branch choice, loop result or type behavior.

### `02-Objects-And-Data`

- Run: scripts such as `PsCustomObject.ps1`, `CsvImportExport.ps1`, `JsonConversion.ps1` and `XmlParsing.ps1`.
- Input: inline sample objects and temporary local sample files where needed.
- Output: object rows, converted JSON, CSV round-trip evidence, grouped summaries or XML attribute output.

### `03-Pipeline-And-Functions`

- Run: `PipelineInputFunction.ps1`, `ParameterValidation.ps1`, `WhatIfSupport.ps1` and related examples.
- Input: pipeline objects, parameter examples and local function metadata.
- Output: accepted input, rejected input, stream behavior, `ShouldProcess` preview or final action state.

### `04-Files-Environment-And-Runtime`

- Run: `JoinPath.ps1`, `FileContent.ps1`, `NativeCommandExitCode.ps1` and `Diagnostic.ps1`.
- Input: local paths, environment values, temp files and runtime state.
- Output: runtime facts, path results, file evidence, native exit-code examples and safe request-shaped output.

### `05-Modules-And-Configuration`

- Run: `Test-PowershellDataFile.ps1`, `Check.ps1`, `Caller.ps1` and configuration samples.
- Input: `Environment.psd1`, shared module functions and local generated sample state.
- Output: validation rows, parse results, configuration records, log records and script exit-code summaries.

### `06-Deployment-And-Git-Training`

- Run: `Deploy-GitRepository.ps1`, then inspect `.sample-*` evidence folders.
- Input: local training key names, package manifests and deployment settings.
- Output: stage summaries, placeholder key evidence, package manifests, deployment receipts and sample logs.

### `07-Operations-And-Directory-Services`

- Run: `CheckADAccount.ps1`, `Scan-ADComputerOU.ps1`, `LDAP-Win-Query.ps1` and related examples.
- Input: local synthetic account, computer, group and OU-shaped values.
- Output: account states, scan counts, group-membership plans, escaped LDAP filters and validation results.

### `08-Backup-And-Compatibility`

- Run: backup, restore, PAS object and compatibility scripts individually.
- Input: local CyberArk-shaped fixture data and generated training receipts.
- Output: backup receipts, restore checks, inventory rows, failed-object categories and compatibility reports.

### `09-PowerShell-Variables`

- Run: read the variable reference files, then run `Invoke-SampleDataExample.ps1`.
- Input: `fixtures/sample-data.json` and markdown examples.
- Output: variable guidance in docs plus fixture summary objects from the sample-data runner.

### `10-Credential-Management`

- Run: scripts in the listed README order, ending with `Test-CredentialSampleSet.ps1`.
- Input: synthetic secret-shaped values, sample credential records and local fixtures.
- Output: redacted credential examples, pattern decisions, token handling rows and boundary statements.

### `11-Deployment-Tool`

- Run: `Test-DeploymentTool.ps1`, then `Invoke-DeploymentTool.ps1 -ReportOnly -Unattended`.
- Input: `fixtures/deployment-tool-config.json` and expected validation counts.
- Output: test results, report-only deployment decisions and `.sample-state/deployment-report.json`.

### `12-Drive-Management`

- Run: `Invoke-SampleDataExample.ps1`.
- Input: `fixtures/sample-data.json`.
- Output: drive-shaped fixture summaries available to later lesson expansion.

### `13-File-Handler`

- Run: `Invoke-SampleDataExample.ps1`.
- Input: `fixtures/sample-data.json`.
- Output: file-handler fixture summaries with lock, file or process-shaped training records.

### `14-Deployment -Repo-Using-Git`

- Run: the three entry scripts and the unit test script listed in the README.
- Input: `fixtures/sample-data.json` plus local deployment settings and class files.
- Output: launcher, refresh and setup plan objects, with tests proving catalogue parsing and validation.

### `15-Testing-And-Validation`

- Run: `Invoke-ValidationLesson.ps1`.
- Input: `fixtures/sample-data.json`.
- Output: assertion-style objects showing expected value, actual value, pass state and validation reason.

### `16-Logging-And-Diagnostics`

- Run: `Invoke-LoggingLesson.ps1`.
- Input: `fixtures/sample-data.json`.
- Output: structured diagnostic rows with run ID, event details and redacted values.

### `17-Remoting-And-Scheduled-Execution`

- Run: `Invoke-ExecutionPlanLesson.ps1`.
- Input: `fixtures/sample-data.json`.
- Output: remoting-shaped and scheduled-run plan objects without opening sessions or registering tasks.

### `18-Module-Packaging`

- Run: `Invoke-ModulePackagingLesson.ps1` with `-View Manifest`, `-View Exports` or `-View Layout`.
- Input: `fixtures/sample-data.json`.
- Output: manifest summary, export decisions or package-layout rows.

### `19-Script-Signing-And-Security`

- Run: `Invoke-SigningSecurityLesson.ps1` with `-View Assessment` or `-View Policy`.
- Input: `fixtures/sample-data.json`.
- Output: signature assessment rows, trusted-publisher decisions and execution-policy summaries.

### `20-Rest-And-Http-Resilience`

- Run: `Invoke-RestResilienceLesson.ps1` with `-View Assessment` or `-View RetryPlan`.
- Input: `fixtures/sample-data.json`.
- Output: status classification, JSON validity, retry decisions, reauth decisions and sanitized diagnostics.

### `21-Parallel-And-CrossPlatform`

- Run: `Invoke-ParallelCrossPlatformLesson.ps1` with `-View Plan` or `-View Platform`.
- Input: `fixtures/sample-data.json`.
- Output: throttle batches, shared-state warnings, supported-platform rows and boundary reasons.

### `22-Error-Taxonomy`

- Run: `Invoke-ErrorTaxonomyLesson.ps1` with `-View Classify` or `-View Retry`.
- Input: `fixtures/sample-data.json`.
- Output: error-category handling decisions, retry limits and fail-fast decisions.

### `23-Argument-Completers`

- Run: `Invoke-ArgumentCompleterLesson.ps1` with `-View Complete` or `-View RegistrationPlan`.
- Input: `fixtures/sample-data.json`.
- Output: completion rows, command names, parameter names, filtered choices and registration-plan data.

### `24-Security-Hardening`

- Run: `Invoke-SecurityHardeningLesson.ps1` with `-View Actions` or `-View Redacted`.
- Input: `fixtures/sample-data.json`.
- Output: hardening actions, severity labels and redacted-safe finding rows.

### `25-Troubleshooting`

- Run: `Invoke-TroubleshootingLesson.ps1` with `-View Plan` or `-View Bundle`.
- Input: `fixtures/sample-data.json`.
- Output: diagnostic plans, first questions, evidence lists and bundle names.

### `26-Capstone-Assessment`

- Run: `Invoke-CapstoneAssessment.ps1` with `-View Summary` or `-View Detail`.
- Input: `fixtures/sample-data.json`.
- Output: learner pass results, missing-section summaries and per-section completion rows.

### `27-Upgrading-WindowsPowerShell-51-To-PowerShell-76`

- Run: read `README.md`, run `Invoke-UpgradeReadinessLesson.ps1`, then scan legacy code with
  `Test-UpgradeReadiness.ps1 -Path <folder>`.
- Input: `fixtures/sample-data.json`, the README examples or a read-only scan of a legacy code folder.
- Output: upgrade decisions and a file, line, pattern, decision, action and evidence worklist.

## Reading outputs

PowerShell may display returned objects as tables or lists depending on the number of properties. The object is still
structured. For predictable display, use:

```powershell
pwsh -NoProfile -NonInteractive -File './24-Security-Hardening/Invoke-SecurityHardeningLesson.ps1' |
    Format-Table -AutoSize
```

When a script creates local evidence, the section README names the folder. Evidence folders named `.sample-*` are safe
to inspect and delete between practice runs.

## Changing sample data

To practise another case, edit only the section's `fixtures/sample-data.json` and rerun the script. Keep the same
property names unless the lesson is specifically about validation failure.

Examples:

- change a REST status code in section `20` to see a different decision
- add a missing capstone section in section `26` to see the pass result change
- change a script publisher in section `19` to test trust decisions

## Failure handling

If a script exits `1`, read the error message first. Most failures mean the fixture path is wrong, JSON is invalid or
the sample data no longer has the expected property names.

Use parser checks when you edit PowerShell:

```powershell
$Path = './20-Rest-And-Http-Resilience/Invoke-RestResilienceLesson.ps1'
$Errors = $null
$Tokens = $null
[System.Management.Automation.Language.Parser]::ParseFile($Path, [ref] $Tokens, [ref] $Errors) | Out-Null
$Errors
```
