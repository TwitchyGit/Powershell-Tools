# Script expansion backlog

The course scripts provide local training behavior, structured output and comment-based help. This backlog lists remaining improvements that would make the course more assessable and closer to production-shaped learning.

## Course-level backlog

- Add Pester tests for reusable functions and expected object properties.
- Add more fixture-driven examples so learners can alter input files without editing script logic.
- Add expected-output files for each unit.
- Add Windows PowerShell 5.1 and Windows PowerShell 7 validation results when a Windows host is available.
- Add live AD, PVWA and AutoSys validation records only after tests run against those systems.
- Add SecretManagement examples for local vault use and secret redaction.
- Add logging examples for transcript, structured JSON logs and correlation identifiers.

## Unit backlog

### 01-Language-Fundamentals

Add short exercises that ask learners to predict output type, version requirement and failure condition.

### 02-Objects-And-Data

Move CSV, JSON, XML and PSD1 examples toward shared fixtures under `fixtures/`.

### 03-Pipeline-And-Functions

Add Pester tests for functions that accept pipeline input and emit structured records.

### 04-Files-Environment-And-Runtime

Add a dedicated logging sample with redaction and retention behavior.

### 05-Modules-And-Configuration

Add module manifests, exported-function checks and module-level tests.

### 06-Deployment-And-Git-Training

Add expected deployment receipt files and negative tests for invalid manifests.

### 07-Operations-And-Directory-Services

Add fixture-driven account sets for disabled, locked, stale and missing-owner records.

### 08-Backup-And-Compatibility

Add fixture-driven restore mismatch tests and Windows host validation records.
### Credential-Management

Add optional Windows live labs for DPAPI portability, Credential Manager, Start-Process -Credential and WinRM.
