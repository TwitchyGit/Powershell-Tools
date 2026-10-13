# Repository refresh training

This unit teaches the shape of a repository refresh and setup workflow without contacting a Git remote, changing
folders, changing ACLs, asking for credentials or opening a remote session.

The scripts use `fixtures/sample-data.json` and return structured objects that describe the stages a real deployment
tool would need. They are training lessons, not deployment tools.

## Files

- `Run-Pull-Repo.ps1`: shows the launcher stage for each sample package.
- `Invoke-RepoRefresh.ps1`: shows the refresh engine stages for the first sample package.
- `Configure-Deployment.ps1`: shows the setup stage for each sample package.
- `DeploymentSettings.ps1`: contains the catalogue and validation functions used by the tests.
- `Classes/`: keeps the class models used by the original design and static tests.
- `Tests/Test-DeploymentTool.ps1`: parses the unit and checks catalogue validation rules.
- `fixtures/sample-data.json`: holds package, environment and host examples.

## Run order

```powershell
pwsh -NoProfile -NonInteractive -File ./Run-Pull-Repo.ps1
pwsh -NoProfile -NonInteractive -File ./Invoke-RepoRefresh.ps1
pwsh -NoProfile -NonInteractive -File ./Configure-Deployment.ps1
pwsh -NoProfile -NonInteractive -File ./Tests/Test-DeploymentTool.ps1
```

Each entry script exits `0` when the training example completes and `1` when fixture loading or validation fails.

## What the examples show

`Run-Pull-Repo.ps1` shows how a launcher chooses an environment, reads package records and emits one refresh plan per
package. The output includes environment, branch, host list, package name, source path and destination.

`Invoke-RepoRefresh.ps1` shows the engine view of one package. It names the source, destination, target branch and the
main stages: verify source, check hosts, archive target, fetch branch and restore on failure.

`Configure-Deployment.ps1` shows the setup view of the same package records. It uses synthetic service-account names
and emits one setup plan per package.

`Tests/Test-DeploymentTool.ps1` keeps the stricter validation checks around catalogue shape and unsafe paths.

## Training boundary

This unit does not:

- call `git`
- prompt for credentials
- change ACLs
- remove folders
- call WinRM
- contact remote hosts
- validate a live source-control server

Live deployment would need a separate implementation and separate Windows, Git, credential, remoting and rollback
validation.

## Extension ideas

- Add fixture cases for missing packages, unsafe paths and unknown package names.
- Add Pester tests that assert the stage output for each script.
- Add a report export example that writes the stage output to JSON.
- Add a capstone lesson that compares planned deployment stages with actual validation results.
