# Git-Deployment-Manager

Deploys, configures and tests the tools listed in `Config\Environment.psd1` on the
servers assigned to each tool for a given environment. Deployment of each tool's own
repository happens over one of three methods, set per environment by
`Environments.<Env>.SourceMethod`: `Git` (the default when unset), `ZipFile`, or `WGET`.

## Files

Entry scripts (run directly):

- `Invoke-Deployment.ps1` - the orchestrator. Deploys, configures and tests every tool
  for one environment.
- `Prepare-Deployment.ps1` - dot-sourced once per console session. Collects credentials
  and a GitLab token so later `Invoke-Deployment.ps1` calls in the same console do not
  ask again, then runs the three `Install\` scripts below as a pre-flight pass.
- `Setup-GitRepoKeys.ps1` - provisions one SSH deploy key per host, per repository.
- `Deploy-GitRepository.ps1` - clones a git repository onto a host list over SSH, using
  a key `Setup-GitRepoKeys.ps1` already provisioned there.
- `Install\Check.ps1` - pre-flight check of one host: PowerShell version, elevation,
  git/ssh tools, `Config\Environment.psd1`, WinRM to every target, deploy-key folder
  access.
- `Install\Test-PowershellDataFile.ps1` - validates `Config\Environment.psd1`: parses
  cleanly, has no duplicate keys, passes the configuration consistency check for every
  environment in the file.
- `Install\Test-DeployKey.ps1` - checks a GitLab API token can list a project's deploy
  keys.

Modules (imported by the entry scripts, not run directly):

- `Config\PSFunctions.psm1` - logging (`LogOutput`/`LogWarn`/`LogError`/`LogDebug`), the
  error/warning popup window, `Show-DeploymentHelp`, and shared helpers (GitLab project
  path, default key path, WinRM reachability, REST error parsing).
- `Config\DeploymentFunctions.psm1` - orchestrator-only helpers: config validation,
  `$Token` resolution, git repository state/branch resolution, running a tool's
  Configure/SetCredentials/UnitTest steps on a host.
- `Config\AltSourceFunctions.psm1` - the `ZipFile`/`WGET` deployment and existence-check
  functions, used when `SourceMethod` is not `Git`.

Data:

- `Config\Environment.psd1` - every environment and tool definition. Read by
  `Invoke-Deployment.ps1`, `Prepare-Deployment.ps1`, `Install\Check.ps1` and
  `Install\Test-PowershellDataFile.ps1`.

## Usage

```powershell
.\Invoke-Deployment.ps1 -Env ENG
.\Invoke-Deployment.ps1 -Env ENG -Tool 'System-Checks'
.\Invoke-Deployment.ps1 -Env PROD -Check
.\Invoke-Deployment.ps1 -Env PROD -Force -NoPopup
.\Invoke-Deployment.ps1
.\Invoke-Deployment.ps1 -Help
```

The last two forms print the help text and exit; neither needs `-Env`.

To collect every credential and the GitLab token once for a console session, dot-source
`Prepare-Deployment.ps1` first:

```powershell
. .\Prepare-Deployment.ps1 -Env ENG
.\Invoke-Deployment.ps1 -Env ENG
```

## `Invoke-Deployment.ps1` run order

1. Import `Config\PSFunctions.psm1`, `Config\DeploymentFunctions.psm1`,
   `Config\AltSourceFunctions.psm1`.
2. No `-Env` given, or `-Help` given: print the help text (`Show-DeploymentHelp`) and
   exit. Nothing else below runs.
3. Run `Install\Test-PowershellDataFile.ps1`. A non-zero exit code stops the run here.
   Checks every environment in the file, not only `-Env`.
4. Read `Config\Environment.psd1`.
5. Confirm this host and script folder are the environment's designated self location
   (`Environments.<Env>.SelfServer`/`SelfDest`). Not the right host or folder, or `-Env`
   not found: stop.
6. Read `Environments.<Env>.SourceMethod` once for the rest of the run.
7. Fill in any of `-AdminUser`/`-ServiceAccount`/`-LDAPTestUser`/`-ApiToken` not passed
   on the command line from the session's own global variables, if `Prepare-Deployment.ps1`
   set them earlier. Under `-Check`, `AdminUser`/`ServiceAccount`/`LDAPTestUser` are
   never filled in this way.
8. `SourceMethod` is `Git` or unset, `-Check` is not set, and no `-ApiToken` was
   supplied: prompt for one.
9. Set up the log file and, unless `-NoPopup` or there is no desktop, the error/warning
   popup window.
10. Self-update: update Git-Deployment-Manager's own checkout, unless `-PreserveSelf`
    was passed.
    - `SourceMethod` is `Git`/unset: read the repository's current state, resolve which
      branch to deploy, clone it into this script's own folder using
      `Setup-GitRepoKeys.ps1` and `Deploy-GitRepository.ps1`, then re-launch this same
      script from the freshly updated file.
    - `SourceMethod` is `ZipFile`/`WGET`: deploy the same way into this script's own
      folder using the matching function in `Config\AltSourceFunctions.psm1`, then
      re-launch.
    - `-Check` is set: report what self-update would do, take no action, do not
      re-launch.
    - Runs the configuration consistency check on `Config\Environment.psd1` once, here.
11. Build the tool list for `-Env`: `CyberArkAPI` first if present and not excluded by
    `-Tool`, then every other tool in the file's own order.
12. `-Check` is not set: collect whichever of `AdminUser`/`ServiceAccount`/`LDAPTestUser`
    the in-scope tools' `Configure`/`SetCredentials`/`UnitTest` steps actually reference,
    plus one credential per distinct `RunAs` account those steps use.
13. For each tool, for each of its hosts (`PrimaryServer` first, then each
    `FailoverServer`):
    - Deploy the tool's repository using `SourceMethod`'s method (or, under `-Check`,
      report what that method would do).
    - Run `Configure` on this host.
    - This host is `PrimaryServer`: also run `SetCredentials`, then `UnitTest`
      (`RTBSteps` or `CTBSteps`, chosen by the environment's `EnvironmentType`).
14. Print one summary line per tool, then the total warning/error counts. Exit `1` if
    any tool did not complete every stage or any error was logged; `0` otherwise.

No parallelism anywhere in this sequence: one tool at a time, one host at a time, one
stage at a time.

## `Invoke-Deployment.ps1` arguments

| Parameter | Required | Type | What it does |
|---|---|---|---|
| `-Env` | Yes (unless `-Help`) | string | Environment name, must match a key under `Environments`. |
| `-Tool` | No | string[] | Restrict the run to these tool names. |
| `-Check` | No | switch | Report only; deploy nothing, run no `Configure`/`SetCredentials`/`UnitTest`. |
| `-Force` | No | switch | For the git path: auto-confirm rather than prompt when the local repository state needs a decision, and auto-pick the resolved default branch rather than prompting when a newer branch exists. |
| `-AdminUser` | No | PSCredential | Vault Administrator account. Prompted for if omitted and a tool in scope needs it. |
| `-ServiceAccount` | No | PSCredential | OS credential for the environment's `ServiceAccount`. Prompted for if omitted and needed. |
| `-LDAPTestUser` | No | string | LDAP test account username (plain string, never a password). Prompted for if omitted and needed. |
| `-ApiToken` | No | SecureString | GitLab API token. Prompted for once if omitted and `SourceMethod` is `Git`/unset; never used under `ZipFile`/`WGET`. |
| `-AllowReadWrite` | No | switch | Passed to `Setup-GitRepoKeys.ps1` for a read-write deploy key. No effect under `ZipFile`/`WGET`. |
| `-PreserveSelf` | No | switch | Skip self-update for this run. |
| `-NoPopup` | No | switch | Do not open the error/warning popup window; the errors file is still written. |
| `-Help` | No | switch | Print usage and the `$Token` resolution table, then exit. |
| `-Verbose`, `-Debug` | No | switch | Standard `[CmdletBinding()]` switches. |

## `Prepare-Deployment.ps1` arguments

| Parameter | Required | Type | What it does |
|---|---|---|---|
| `-Env` | Yes | string | Must match a key under `Environments`. Read to decide whether `LDAPTestUser` is prompted for (skipped when that environment's `EnvironmentType` is `RTB`), and echoed in the summary. Not passed on to `Invoke-Deployment.ps1`. |

Must be dot-sourced (`. .\Prepare-Deployment.ps1 -Env ENG`), not run directly, or the
credentials it collects do not survive into the console session.

Prompts in order for `AdminUser`, `ServiceAccount`, `LDAPTestUser` (username first, `Enter`
to skip; `AdminUser`/`ServiceAccount` then prompt for a password via `Get-Credential`,
`LDAPTestUser` does not), then requires an `ApiToken`. Then runs, in order:
`Install\Test-PowershellDataFile.ps1`, `Install\Test-DeployKey.ps1` (only if `SelfRepo`
can be read from `Config\Environment.psd1`), `Install\Check.ps1 -Quiet -Env <Env>`.
Prints `Invoke-Deployment.ps1`'s option list, then a `Collected:`/`Skipped:` summary of
which of the four values ended up set in the session.

## `Setup-GitRepoKeys.ps1` arguments

| Parameter | Required | Type | What it does |
|---|---|---|---|
| `-Servers` | Yes | string | Comma-separated host list. |
| `-Repo` | Yes | string | Repository, e.g. `cyberark_password_vault-repo/system-checks.git`. |
| `-ApiToken` | No | SecureString | GitLab token, scope `api`, role Maintainer or above. Prompted for if omitted. |
| `-GitLabHost` | No | string | Defaults to `host.company.com`. |
| `-KeyPath` | No | string | Private key path on each host. Defaults to a path derived from `-Repo`. |
| `-AllowReadWrite` | No | switch | Registers a read-write key. Omit for a read-only key. |
| `-CredentialCleanup` | No | switch | Before provisioning, removes existing SSH private keys from the executing account's `.ssh` folder, clears loaded `ssh-agent` identities, removes matching GitLab entries from Windows Credential Manager, unsets the global git `credential.helper`. Off by default. |

Generates an ed25519 keypair on each target host (`ssh-keygen.exe`), locks the key
folder and file to `SYSTEM`, `BUILTIN\Administrators` and the executing account with
`icacls.exe`, then registers the public key as a GitLab deploy key and verifies it with
an SSH connection - both of those two steps run from wherever this script itself
executes, not from the target host. The private key never leaves the host it was
generated on. Re-running against a host that already has a key at the same path reuses
it. An already-registered key with a different access level is updated to match
`-AllowReadWrite`.

Each repository gets its own keypair, even on a host that deploys more than one: the
default `-KeyPath` is `C:\ProgramData\Git-Deployment-Manager\keys\gitlab_deploy_<repo-slug>_ed25519`.

## `Deploy-GitRepository.ps1` arguments

| Parameter | Required | Type | What it does |
|---|---|---|---|
| `-Servers` | Yes | string | Comma-separated host list. |
| `-Repo` | Yes | string | Repository, e.g. `cyberark_password_vault-repo/system-checks.git`. |
| `-Dest` | Yes | string | Target directory to clear and clone into, e.g. `C:\System-Checks`. |
| `-Branch` | Yes | string | Branch or tag to clone. Accepted but unused under `-Check`. |
| `-KeyPath` | No | string | Private key path on each host. Defaults to the same path `Setup-GitRepoKeys.ps1` derives from `-Repo`. |
| `-GitLabHost` | No | string | Defaults to `host.company.com`. |
| `-Check` | No | switch | Read-only: for each host, reports whether `-Dest` is an existing clone, its branch, and which remote branches are ahead of the remote's actual default branch (read via `git ls-remote --symref`). Writes the result to `-CheckOutputPath` as JSON. No wipe, no clone. |
| `-CheckOutputPath` | Required with `-Check` | string | File path for the `-Check` JSON result. |

Expects the deploy key to already exist at `-KeyPath`; does not create one. Fails
cleanly, per host, if that host has no key there yet. On a successful clone, sets
`core.sshCommand` in the clone's own git config to the same key, so later git commands
or an editor on that host pick it up without needing this script's own environment
variable. Whether the key can push was decided when `Setup-GitRepoKeys.ps1` registered
it; this script has no equivalent switch.

## `Install\Check.ps1` arguments

| Parameter | Required | Type | What it does |
|---|---|---|---|
| `-Env` | Yes | string | Scopes every per-environment check (configuration consistency, WinRM reachability, deploy key folder access) to this one environment. |
| `-Quiet` | No | switch | Suppress per-check `PASS` lines; `FAIL` lines and the summary still print. |

Checks, in order: PowerShell 7.6+ present, running elevated, Windows PowerShell 5.1
present, `git.exe` reachable, `ssh.exe`/`ssh-keygen.exe` reachable,
`Config\Environment.psd1` parses (`Install\Test-PowershellDataFile.ps1`),
`Config\PSFunctions.psm1`/`Config\DeploymentFunctions.psm1` import cleanly, WinRM
loopback to this host, self-location match for every environment (informational), the
one environment's configuration consistency, WinRM reachability to every host in that
environment's `ToolList`, `BUILTIN\Administrators` access on each reachable host's
deploy-key folder, and that the log directory exists or can be created. Never checks
the GitLab API token itself.

## `Install\Test-PowershellDataFile.ps1` arguments

| Parameter | Required | Type | What it does |
|---|---|---|---|
| `-Path` | No | string | Defaults to `Config\Environment.psd1` next to this script. |

Parses the file, confirms it is exactly one top-level hashtable with no executable
content beyond `$true`/`$false`/`$null`, confirms `Tools` and `Environments` have no
duplicate key silently dropped by the parser, then runs the configuration consistency
check for every environment in the file and prints a full field-by-field extract of
each environment's block (including `ToolList`, one line per tool). Writes each problem
as an `ERROR:` line. Exits `1` if any problem was found, `0` otherwise.

## `Install\Test-DeployKey.ps1` arguments

| Parameter | Required | Type | What it does |
|---|---|---|---|
| `-Repo` | Yes | string | Repository, e.g. `cyberark_password_vault-repo/system-checks.git`. |
| `-GitLabHost` | No | string | Defaults to `host.company.com`. |
| `-ApiToken` | No | SecureString | Prompted for if omitted. |

Makes one GitLab API call (list deploy keys for the project) and prints `SUCCESS` plus
the result, or the failing HTTP status and body. Exits `0` on success, `1` otherwise.
Provisions nothing.

## Configuration file: `Config\Environment.psd1`

Read with `Import-PowerShellDataFile`. Four top-level keys: `SelfRepo`, `GitLabHost`,
`WgetHost`, `LogDir`, plus `Environments` and `Tools`.

- `SelfRepo` - Git-Deployment-Manager's own repository, same shape as any tool's `Repo`
  field. Used for self-update.
- `GitLabHost` - one value for every environment, passed to
  `Setup-GitRepoKeys.ps1`/`Deploy-GitRepository.ps1` calls the orchestrator makes.
- `WgetHost` - one value for every environment, used only when `SourceMethod` is
  `WGET`: the directory a target host lists to find the file matching
  `<ToolName>*.zip`.
- `LogDir` - one value for every environment. `Invoke-Deployment.ps1` and
  `Install\Check.ps1` both read it instead of each hardcoding their own path.

`Import-PowerShellDataFile` returns a plain `Hashtable`, whose key order does not
reliably match the file. `Tools`' own file order (used for run order) is read from the
file's AST instead, by `Get-OrderedTopLevelKeys`.

### `Environments`

One block per environment name (`ENG`, `PROD`, etc). Fields:

- `EnvironmentType` - `CTB` or `RTB`.
- `SourceMethod` - `Git`, `ZipFile` or `WGET`. Omit for `Git`.
- `ServiceAccount` - the account name used for `RunAs` and, when collected, the
  matching credential used for `Args`.
- `PACLIVersion`, `PADRVersion`, `EVDVersion`, `BackupPoolName` - plain values read by
  specific tools' `Args`. `BackupPoolName` is used only by `Vault-Backup`.
- `SelfServer`, `SelfDest` - the one host and one directory Git-Deployment-Manager
  itself is allowed to run from for this environment.
- `ToolList` - one entry per tool name: `{ PrimaryServer; FailoverServer }`.
  `FailoverServer` is an array, `@()` if the tool has no failover host. Each
  environment has its own list; a tool with no entry here is skipped for this
  environment.

### `Tools`

One entry per tool name. Fields:

- `Repo`, `Dest` - repository path, target `C:\` directory.
- `Configure` - `{ RunAs; Steps }`. `Steps` is an ordered array of `{ Script; Args }`,
  run in list order under the one `RunAs`, on every host.
- `SetCredentials` - `{ RunAs; Script; Args }`, one script, no `Steps` array. Optional.
  Runs after `Configure`, on `PrimaryServer` only.
- `UnitTest` - `{ RunAs; RTBSteps; CTBSteps }`. Optional. Each of `RTBSteps`/`CTBSteps`
  is an ordered array of `{ Script; Args }`; only the one matching the environment's
  `EnvironmentType` runs. Runs on `PrimaryServer` only, after `SetCredentials`.

Stage order per tool is fixed: `Configure`, then `SetCredentials`, then `UnitTest`. A
stage key not present on a tool is skipped.

### `Args`

A hashtable, not an array: `'-FlagName' = '$Token'`. A `$`-prefixed string value is
resolved at run time (see Token resolution below); a plain string passes through
literally; `$true` is a bare switch with no value, e.g. `'-Check' = $true`.

### `RunAs`

One value per `Configure`/`SetCredentials`/`UnitTest` stage, covering every step in it:
either the literal `Administrator`, or a quoted `$Token`, e.g. `'$ServiceAccount'`.

### Token resolution

A `$`-prefixed string in `Args` or `RunAs` is a placeholder this tooling resolves, not
PowerShell - `Config\Environment.psd1` has no variable expansion of its own.

In `Args`:

| Token | Resolves to |
|---|---|
| `$AdminUser`, `$ServiceAccount` | The collected credential, a `PSCredential` object. |
| `$LDAPTestUser` | The collected username, a plain string. |
| `$Env` | The environment name from `-Env`. |
| `$Name` (any other) | `Environments.<CurrentEnv>.<Name>`, e.g. `$BackupPoolName`, `$PADRVersion`. |

In `RunAs`, every `$Name` token, `$ServiceAccount` included, resolves instead to
`Environments.<CurrentEnv>.<Name>`, the plain account name - never a credential. The
credential for that account is separately matched by user name from whichever of
`-ServiceAccount`/an interactive prompt supplied it.

### Example

```powershell
Environments = @{
    ENG = @{
        EnvironmentType = 'CTB'
        ServiceAccount  = 'svc-eng-example'
        PACLIVersion    = 'v14.6'
        SelfServer      = 'server0'
        SelfDest        = 'C:\Git-Deployment-Manager'
        ToolList        = @{
            'System-Checks' = @{ PrimaryServer = 'server1'; FailoverServer = @('server2', 'server3') }
        }
    }
}

Tools = @{
    'System-Checks' = @{
        Repo           = 'example-org/example-deploy-repos/system-checks.git'
        Dest           = 'C:\System-Checks'
        Configure      = @{
            RunAs = 'Administrator'
            Steps = @(
                @{ Script = 'Set-Configuration.ps1'
                   Args   = @{ '-Env' = '$Env'; '-ServiceAccount' = '$ServiceAccount' } }
            )
        }
        SetCredentials = @{
            RunAs = '$ServiceAccount'; Script = 'Create-Credentials.ps1'
            Args  = @{ '-AdminUser' = '$AdminUser' }
        }
        UnitTest       = @{
            RunAs    = '$ServiceAccount'
            RTBSteps = @(
                @{ Script = 'Run-UnitTests.ps1'
                   Args   = @{ '-ServiceAccount' = '$ServiceAccount'; '-AdminUser' = '$AdminUser'; '-Check' = $true } }
            )
            CTBSteps = @(
                @{ Script = 'Run-UnitTests.ps1'
                   Args   = @{ '-ServiceAccount' = '$ServiceAccount'; '-AdminUser' = '$AdminUser'; '-Check' = $true } }
            )
        }
    }
}
```

## Role behavior

- `PrimaryServer`: deploys the tool, then runs `Configure`, `SetCredentials` (if
  defined) and `UnitTest`.
- `FailoverServer`: deploys the tool, then runs `Configure` only.

This is per tool per environment, not per host: one host can be primary for one tool,
failover for another, and hold a different role again under a different `-Env`.

## Deploy keys (`SourceMethod` = `Git`)

Every host is provisioned as one of two things, decided by whether `-AllowReadWrite`
was passed to `Setup-GitRepoKeys.ps1` for it:

- No `-AllowReadWrite` (default): a read-only key. The host can only pull.
- `-AllowReadWrite`: a read-write key. The host can commit and push as well as pull.

Both are SSH keys only - there is no HTTPS or token-based path for cloning, so no
credential sits in a remote URL or a `.git\config` file. Run `Setup-GitRepoKeys.ps1`
against a host once per repository before the first `Deploy-GitRepository.ps1` call
there; re-running it later is safe and reuses the existing key. Each repository gets
its own keypair, even on a host that deploys more than one repository.

## Failure handling

- Wrong host or folder for `-Env`'s `SelfServer`/`SelfDest`: stop before self-update
  starts.
- Self-update fails: stop the entire run. The one exception to every rule below, which
  all apply only once self-update has already succeeded.
- A tool's deploy step fails on a host: stop that tool on that host, skip `Configure`,
  `SetCredentials`, `UnitTest` for it, move to the tool's next host.
- A `Configure` step, `SetCredentials` or a `UnitTest` entry fails: report it, continue
  with the remaining steps/stages/entries for that tool.
- Per-tool issues are collected and reported together when that tool finishes; the full
  run prints one consolidated summary at the end covering every tool attempted.
- Exit code `1` when any error was logged or any tool did not complete every stage;
  `0` otherwise. A tool with no `ToolList` entry for `-Env` is listed as not deployed
  and does not affect the exit code.

## Output and logging

- `Config\PSFunctions.psm1`'s `LogOutput`/`LogWarn`/`LogError`/`LogDebug` write to the
  console and, once set up, the run's log file (`<LogDir>\Deploy_<timestamp>.log`).
  `LogWarn`/`LogError` also write to the error/warning popup window's own file.
  Each line is tagged with the tool and stage running when it was written.
- The popup window (unless `-NoPopup`, or there is no desktop) opens at script start
  and tails that file live; it stays open after the run ends.
- Remote script blocks cannot call these functions directly; they write through
  `Write-Warning`/`Write-Verbose`/`Write-Debug` instead, which `Write-RemoteLog` then
  passes into the same logging functions on return.
- `-Verbose`/`-Debug` on `Setup-GitRepoKeys.ps1` or `Deploy-GitRepository.ps1` are
  threaded into each host's own remote session, not just the local console, so a
  failure on one host shows what happened on that host specifically. Each host's
  `Invoke-Command` call runs to completion before the next one starts, so one host's
  output is never interleaved with another's.
