# Repository Refresh Runbook

## 1. Purpose

This toolset refreshes a set of software packages on one primary host and any number of secondary hosts. For each package it replaces the contents of the package folder with a clean copy taken from the central source-control server. It can then apply environment-specific setup on the primary host.

The toolset has two jobs, each with its own entry point:

1. **Refresh**: bring the package folders up to date from source control.
2. **Setup**: apply configuration and credentials to the refreshed packages.

## 2. Parts

| Part | Role |
|------|------|
| Launcher | Interactive front end for the Refresh job. Collects answers, shows a summary and calls the Engine once per package. |
| Engine | Does the actual work of replacing a package folder on every target host. |
| Settings Library | Holds the package catalogue, per-environment values and the Setup routine. |
| Configurator | Interactive front end for the Setup job. Collects credentials, shows a summary and calls the Setup routine. |

Typical order of use: run the Launcher first, then the Configurator.

## 3. Requirements

- Run from an elevated (administrator) session.
- PowerShell 7.6 or later on the machine that runs the tools.
- Git for Windows on the machine that runs the tools and on every target host.
- Remote management access to each secondary host, using the PowerShell 7 remote endpoint.
- A shared helper module installed at the same fixed location on every target host. It is used to release folders held open by running programs.
- A source-control account and access token with read permission on the packages.
- Every package folder must live under drive C.

## 4. Package catalogue

The Settings Library holds one list of packages. Each entry has three fields:

- **Name**: short label used to select the package.
- **Source path**: location of the package on the source-control server, in the form `group/project.git`.
- **Folder**: where the package lives on disk, always below drive C.

The catalogue is checked every time a tool starts (see Catalogue Check below). A package is skipped with a warning if its folder does not exist yet. Folders are never created by the Launcher, so a package is only refreshed on hosts where it was installed first.

## 5. Environments

Two environments exist: NONPROD and PROD.

| Environment | Release branch | Source of packages |
|-------------|----------------|--------------------|
| NONPROD | development release branch | Source-control server, credentials required |
| PROD | production release branch | Source-control server, credentials required |

Each environment also has its own set of version numbers and a backup pool name. These are used only by the Setup job.

## 6. Refresh job

### 6.1 Launcher flow

1. Load the Settings Library and run the Catalogue Check. A bad catalogue or an unknown package name stops the run.
2. Ask for the environment if it was not supplied.
3. Pick the release branch and the source of packages from the environment (section 5).
4. For environments that use the source-control server, ask for the account name and the access token. Ask whether the token should be removed from the local copy once finished.
5. Ask for a comma-separated list of secondary hosts. The local host is always added as the primary target. An empty answer means local only.
6. Print a summary of every choice. Wait for confirmation.
7. Confirm Git is available on this machine.
8. Print the uncommitted-changes report for every selected package folder (see 6.2). Wait for a second confirmation.
9. For each selected package: call the Engine, grant the current user full control of the folder and optionally strip the token from the local copy (see 6.3).
10. Return to the starting folder and exit with code 0.

Package folders that do not exist are skipped with a warning at steps 8 and 9.

### 6.2 Safety pause

The Launcher does not touch any folder until the operator has seen what is in it. Step 8 lists every uncommitted or untracked file in each package folder. The operator must either commit those changes by hand or accept that they will be lost, then press return. Pressing Ctrl-C stops the run with nothing changed.

### 6.3 Token clean-up

If the operator chose to remove the token, the local copy of each package is reset to point at the plain server address with no credentials in it. This step applies to the local host.

### 6.4 Engine inputs

| Input | Meaning |
|-------|---------|
| Servers | Comma-separated host list. |
| User | Source-control account name. |
| Token | Access token, as plain text or protected text. |
| Repo | Source path of the package. |
| Dest | Folder to replace. |
| Branch | Branch or tag to fetch. |
| Verbose and Debug switches | Extra diagnostic output. |

Running the Engine with no inputs prints a usage message and exits with code 1.

### 6.5 Engine stages

The Engine runs in three phases.

**Phase A: input checks and relaunch**

1. **Input Check**. Every input is tested against a strict pattern before anything else happens.
   - Hosts: letters, digits, dot, underscore and hyphen only.
   - User: the same character set.
   - Source path: `group/project` style, no parent-folder segments.
   - Branch: must start with a letter or digit and contain no spaces.
   - Folder: must be strictly below drive C, using plain characters only, with no parent-folder segments.
   - Token: must not be empty.

   All failures are listed together, then the run exits with code 1.
2. **Self-Copy Relaunch**. The Engine copies itself to a uniquely named temporary file and runs that copy in a fresh process. This allows the package folder to be replaced even when the Engine itself lives inside it. The token is passed to the child in protected form. The child's exit code becomes the parent's exit code. The temporary file is deleted afterwards and the original folder and diagnostic state are restored.

**Phase B: checks on the relaunched copy**

3. **Source Verification**. The Engine builds the credentialed address in memory and asks the server whether the requested branch exists. A masked version of the address is used in all printed output. If Git is missing or the branch is not found, the run exits with code 1.
4. **Host Readiness Check**. Every target host is tested before any of them is changed. A host fails if it cannot be reached for remote management, if the PowerShell 7 endpoint cannot be used, or if the shared helper module is absent. If any host fails, the Engine reports the list and exits with code 1. No host is changed in that case.

**Phase C: replacement on each host**

5. **Per-Host Replacement**. Hosts are processed one after another. On each host the following happens:
   1. Add Git to the search path. If Git is still missing, report failure for this host and move on.
   2. Make sure the package folder exists.
   3. **Safety Archive**: compress the current contents of the folder into a temporary archive. If this fails, nothing is removed and the host is reported as failed.
   4. **Lock Release**: load the shared helper module and stop any program holding files open under the folder. Programs that cannot be stopped are listed as warnings. A failure here is a warning only.
   5. **Folder Removal**: delete the folder. If files remain, move the folder aside to a temporary name instead. If both attempts fail, restore the archive, clean up and report failure for this host.
   6. **Fresh Copy**: fetch the single requested branch into the folder with a slow-connection timeout of 30 seconds. Output is scrubbed so the token never appears.
   7. **Rollback**: if the fetch fails or the folder is missing afterwards, delete whatever is there and restore the archive.
   8. **Success**: delete the archive and report the host as complete.
6. **Wrap-Up**. The token and address are cleared from memory. If any host failed, the Engine lists them and exits with code 1. Otherwise it exits with code 0.

### 6.6 Protections built into the Engine

- All hosts are checked before any host is changed.
- A backup archive exists for the whole time the folder is empty or being replaced.
- A failed fetch restores the previous contents.
- The token is never printed and is held as protected text between processes.
- Input patterns prevent path escapes and unexpected characters reaching the host.
- Any failure on any host gives exit code 1 at the end, even when other hosts succeeded.

### 6.7 Engine helper

**Secret Unwrapper**: converts protected text back to plain text for use in the server address and clears the temporary memory immediately after.

## 7. Setup job

### 7.1 Configurator flow

1. Load the Settings Library and run the Catalogue Check on the requested names.
2. Ask for the environment if it was not supplied.
3. Ask for two credentials if not supplied: the service account for the environment and the administrator account for the credential vault.
4. Work out the service account for backup-related packages. PROD uses the same account as the main one. NONPROD uses a fixed separate account.
5. Look up the environment values (see Environment Lookup).
6. Print a summary of every choice. Wait for confirmation.
7. Call the Setup routine (see Configuration Runner).
8. Clear the credentials from memory, return to the starting folder and exit with code 0 on success or 1 on any failure.

### 7.2 Package setup recipes

Each package has its own recipe. Recipes live inside the Configuration Runner so they can use the values collected earlier.

| Package | Setup action | Credential action |
|---------|--------------|-------------------|
| Repo1 | Run the package setup script with the main service credential and the first version value. | None |
| Repo2 | Run the package setup script with the main service account name. | None |
| Repo3 | Run the package setup script with the main service account name. | Create vault credentials |
| Repo4 | Run the package setup script with the backup service account and the second version value. | Create vault credentials |
| Repo5 | Remove the old replication program. If that succeeds run the package setup script with the backup service account, the third version value and the backup pool. Then register the event log. | Create vault credentials |

## 8. Settings Library functions

**Environment Lookup**
- Input: environment name.
- Output: the set of version numbers and backup pool name for that environment.

**Catalogue Check**
- Input: optional list of package names. Names may be separated by commas.
- Checks every catalogue entry: name present and unique, source path well formed and folder strictly below drive C with no parent-folder segments.
- Stops with one combined message if any entry is bad.
- With no names given, returns the whole catalogue.
- With names given, stops on any unknown name and lists the valid ones. Otherwise returns only the matching entries.

**Configuration Runner**
- Input: environment, the two service account names, the service credential, the administrator credential and an optional package list.
- Steps:
  1. Fetch environment values.
  2. Build the setup recipes.
  3. Stop if a recipe refers to a package missing from the catalogue.
  4. Keep only the recipes for the selected packages.
  5. For each recipe:
     - Skip with a warning if the package setup folder does not exist.
     - Enter the folder and run the setup action with strict error handling.
     - Record the folder as failed if the action raised an error or ended with a non-zero code.
     - If the action succeeded and a credential action exists, run it on the local host through a remote session that uses the service credential. Print the output. A failure here is printed but does not mark the folder as failed.
     - If the action failed, skip the credential action with a warning.
     - Always return to the previous folder.
  6. If any folder failed, stop with one message listing them.

## 9. Exit codes

Every entry point returns only 0 or 1.

| Code | Meaning |
|------|---------|
| 0 | Everything requested finished. |
| 1 | Input rejected, a prerequisite was missing, a host check failed, any host failed or any setup action failed. |

## 10. Running the tools

Refresh, fully interactive:

```powershell
.\Run-Pull-Repo.ps1
```

Refresh, with everything supplied up front:

```powershell
.\Run-Pull-Repo.ps1 -Env PROD -GitUser <account> -GitToken <protected-text> `
    -FailoverHost "host1.example,host2.example" -RepoName Repo1,Repo2
```

Setup:

```powershell
.\Configure-Deployment.ps1 -Env PROD -RepoName Repo3
```

Add `-Verbose` or `-Debug` to the Engine for step-by-step output. Both can expose more detail in the console, so use them only when needed.

## 11. Troubleshooting

| Symptom | Likely cause | Action |
|---------|--------------|--------|
| Input check lists errors then exits | A value broke one of the patterns in 6.5 | Fix the listed value and rerun. |
| Branch not found | Wrong branch name or the token lacks access | Confirm the branch exists and the token can read the package. |
| Host check failed, nothing changed | Remote access off, endpoint missing or helper module absent | Fix the host named in the warning, then rerun. |
| Folder could not be removed, previous files restored | A program still holds files open and could not be stopped | Stop the program by hand and rerun. |
| Fetch failed, previous files restored | Network problem or bad credentials | Check connectivity and the token, then rerun. |
| Package skipped with a missing-folder warning | Package not installed on this host | Install the package first if it is meant to be there. |
| Setup skipped credentials for a package | The setup action failed first | Fix the setup error and rerun the Configurator for that package. |
| Unknown package name | Name not in the catalogue | Use one of the valid names shown in the message. |

## 12. Adding a package

1. Add a catalogue entry with a unique name, a source path and a folder below drive C.
2. If the package needs setup, add a matching recipe in the Configuration Runner using the same name.
3. Run either tool once with `-RepoName` set to the new name to confirm the catalogue passes the Catalogue Check.
