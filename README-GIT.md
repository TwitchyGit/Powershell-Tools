# Git Tools

Two scripts, run in a fixed order against a host list. Both are SSH only, there is no
HTTPS or token-based path, so there is never a credential embedded in a remote URL or
sitting in a `.git\config` file to leak.

## The two roles

Every host is provisioned as one of two things, decided entirely by whether
`Setup-GitRepoKeys.ps1 -AllowPush` was passed for it:

- **Operations hosts** (default, no `-AllowPush`): get a read-only deploy key. They can
  only ever pull from GitLab. Any change to the repository has to go through
  gitlab.company.com directly, the key cannot push.
- **Engineer hosts** (`-AllowPush`): get a read-write deploy key, so the host has full git
  access, commits, pushes, pulls, working normally through an editor such as VS Code.

## Run order

1. `Setup-GitRepoKeys.ps1` provisions each target host: it generates an ed25519 keypair
   specific to that host and that repository, locks its ACLs down to SYSTEM,
   Administrators and the executing account, registers the public key as a GitLab deploy
   key for the project, read-only unless `-AllowPush` is passed, then verifies the key
   authenticates. Before doing any of that it also removes existing SSH private keys and
   cached GitLab credentials it finds on that host, unless `-SkipCredentialCleanup` is
   passed. The private key never leaves the host it is generated on.

2. `Deploy-GitRepository.ps1` clones (or re-clones) the repository onto each host over SSH,
   using the key from step 1. It expects that key to already exist at the matching
   `-KeyPath`, it does not create one itself. Running it against a host that has not been
   through step 1 fails cleanly with a warning naming that gap. Once cloned, it sets
   `core.sshCommand` in that repository's own config to point at the same key, so an
   engineer's later git commands or VS Code session on that host pick it up automatically,
   without needing this script's environment variable still set.

Run step 1 against a host once per repository. Re-running it later is safe, an existing
key at the same path is reused rather than regenerated. An already-registered deploy key is
treated as success rather than an error.

Each repository gets its own keypair, even on hosts that deploy more than one, the default
`-KeyPath` on both scripts is derived from `-Repo`
(`C:\ProgramData\ssh\gitlab_deploy_<repo-slug>_ed25519`), so two different repositories on
the same host never collide on one shared key.

## Example

Operations host, read-only, deploy-only:

```powershell
$ApiToken = Read-Host -AsSecureString -Prompt "GitLab API token"

.\Setup-GitRepoKeys.ps1 `
    -Servers "eun045838.qaeurope.nom" `
    -Repo "eis-cyberark_password_vault-serverbuilds-eng/system-checks.git" `
    -ApiToken $ApiToken

.\Deploy-GitRepository.ps1 `
    -Servers "eun045838.qaeurope.nom" `
    -Repo "eis-cyberark_password_vault-serverbuilds-eng/system-checks.git" `
    -Dest "D:\System-Checks" `
    -Branch "main"
```

Engineer host, full git access:

```powershell
.\Setup-GitRepoKeys.ps1 `
    -Servers "eun047046.QAEUROPE.NOM" `
    -Repo "eis-cyberark_password_vault-serverbuilds-eng/system-checks.git" `
    -ApiToken $ApiToken `
    -AllowPush

.\Deploy-GitRepository.ps1 `
    -Servers "eun047046.QAEUROPE.NOM" `
    -Repo "eis-cyberark_password_vault-serverbuilds-eng/system-checks.git" `
    -Dest "D:\System-Checks" `
    -Branch "main"
```

`Deploy-GitRepository.ps1` is identical in both cases, the access level was already decided
when the key was provisioned.

## Files

- `Setup-GitRepoKeys.ps1` - provisions and registers the SSH deploy key, run first.
- `Deploy-GitRepository.ps1` - clones the repository over SSH using that key.
