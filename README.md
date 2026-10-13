# PowerShell 7 training repository

This repository is a local PowerShell 7 training course. It teaches syntax, functions, data handling, deployment-shaped
flows, credential boundaries, validation, logging, REST handling, security and troubleshooting through runnable samples.

The material is designed to run from synthetic local data. It does not prove live Windows, Active Directory, WinRM,
CyberArk, AutoSys, Git remote, certificate store or production deployment behavior.

## How to use the course

Start in `COURSE-MAP.md` for the topic order, then use `LEARNER-GUIDE.md` for the command, input and output contract for
each numbered section.

Most sections can be used directly:

```powershell
cd '<repository root>'
pwsh -NoProfile -NonInteractive -File './01-Language-Fundamentals/ArrayIndexing.ps1'
pwsh -NoProfile -NonInteractive -File './18-Module-Packaging/Invoke-ModulePackagingLesson.ps1'
```

The fixture-backed sections read `fixtures/sample-data.json` from their own folder. These fixtures are safe synthetic
records and can be changed to test different training cases.

## What output to expect

Scripts return PowerShell objects where possible, not formatted text. The normal pattern is:

- exit code `0` when the training example completes
- exit code `1` when fixture loading, validation or a scripted check fails
- structured rows with named properties such as `Name`, `Result`, `Decision`, `Status` or `Reason`
- no credential prompts
- no live network calls
- no live remote sessions

Some older lessons create `.sample-*` folders as local evidence. These are training artifacts, not production state.

## Running the whole course

`Invoke-TrainingCourse.ps1` lists the runnable course scripts in order and runs them in child PowerShell processes.
Use individual section commands while learning a topic. Use the course runner when you want a broad local smoke test.

```powershell
pwsh -NoProfile -NonInteractive -File './Invoke-TrainingCourse.ps1' -ContinueOnFailure
```

Helper scripts and class files are parsed by the runner rather than run as standalone lessons.

## Documentation map

- `COURSE-MAP.md`: course order, topic coverage and local sample-data contract.
- `LEARNER-GUIDE.md`: section-by-section run commands, inputs and expected outputs.
- numbered section `README.md` files: topic notes and local safety boundaries.

