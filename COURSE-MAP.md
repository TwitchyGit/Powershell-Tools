# PowerShell 7 training course map

This repository is training material. Scripts should run from local synthetic data, produce structured output and avoid
live AD, WinRM, CyberArk, Git remote, credential prompt or drive-mapping dependencies unless a lesson is explicitly
marked as a live validation exercise.

## Current flow

1. `01-Language-Fundamentals`: syntax, values, control flow, classes, jobs and basic parallel examples.
2. `02-Objects-And-Data`: custom objects, hashtables, CSV, JSON, XML, formatting and data-file inspection.
3. `03-Pipeline-And-Functions`: advanced functions, parameters, validation, pipeline input, streams and `ShouldProcess`.
4. `04-Files-Environment-And-Runtime`: paths, files, providers, environment variables, process inspection, native
   command exits, REST-shaped output and secure strings.
5. `05-Modules-And-Configuration`: helper modules, `.psd1` configuration and generated local sample state.
6. `06-Deployment-And-Git-Training`: deployment-shaped flow with local manifests, local package state and synthetic
   Git-like data.
7. `07-Operations-And-Directory-Services`: AD-shaped account, computer and group examples using local objects.
8. `08-Backup-And-Compatibility`: CyberArk-shaped backup, restore, PAS object and compatibility examples using local
   fixtures.
9. `09-PowerShell-Variables`: variable reference material with fixtures for future runnable lessons.
10. `10-Credential-Management`: safe credential, token, certificate and boundary examples with synthetic secrets.
11. `11-Deployment-Tool`: reusable deployment orchestration classes, fixtures, tests and report generation.
12. `12-Drive-Management`: drive-mapping module material with local fixture examples.
13. `13-File-Handler`: file-lock handling module material with local fixture examples.
14. `14-Deployment -Repo-Using-Git`: repository refresh runbook converted to fixture-backed training output.
15. `15-Testing-And-Validation`: fixture-backed assertions and validation result checks.
16. `16-Logging-And-Diagnostics`: structured logging, redaction and run-correlation examples.
17. `17-Remoting-And-Scheduled-Execution`: remoting-shaped and scheduled-run plans without live execution.
18. `18-Module-Packaging`: module manifest, export and package-layout decisions using local fixtures.
19. `19-Script-Signing-And-Security`: script-signing, publisher trust and execution-policy decisions using local
    fixtures.
20. `20-Rest-And-Http-Resilience`: HTTP response classification, retry and sanitized diagnostics using local fixtures.
21. `21-Parallel-And-CrossPlatform`: throttle, ordering, shared-state and platform-boundary plans using local fixtures.
22. `22-Error-Taxonomy`: terminating, non-terminating, native-exit and retry decisions using local fixtures.
23. `23-Argument-Completers`: command and parameter completion examples using local fixtures.
24. `24-Security-Hardening`: redaction, least privilege, safe temp-file and TLS-boundary examples using local fixtures.
25. `25-Troubleshooting`: diagnostic planning and evidence-bundle examples using local fixtures.
26. `26-Capstone-Assessment`: final local assessment that combines validation, logging, security, REST and reporting.
27. `27-Upgrading-WindowsPowerShell-51-To-PowerShell-76`: upgrade guidance and side-by-side migration examples.

## Sample data contract

Every numbered section has `fixtures/sample-data.json`. Existing lessons should either use their own local synthetic
data or read that fixture when the lesson needs shared records. The root course runner should execute lessons in order
and treat helper files as parse-only.

For learner instructions, expected inputs and expected outputs for each section, use `LEARNER-GUIDE.md`.

## Missing subjects

The current numbered flow covers the identified PowerShell 7 training subjects with local runnable samples. Future
additions should extend the same pattern: a numbered section, `fixtures/sample-data.json`, one or more runnable scripts
and a README that states live-system boundaries.
