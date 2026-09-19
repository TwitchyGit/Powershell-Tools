# Note   : Admin access required to lock down the private key file's ACLs
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Provisions a per-host SSH deploy key for GitLab, entirely from the target host.
.DESCRIPTION
    On each target host this generates a dedicated ed25519 keypair, restricts the private
    key's ACLs to SYSTEM, Administrators and the executing account, registers the public
    key as a read-only GitLab deploy key for the given project, then verifies it works.
    The private key never leaves the host it was generated on. The GitLab API token is
    used only in memory for the single registration call, never written to disk.

    Run this script against a host before running Deploy-GitRepository.ps1 against it.
    Deploy-GitRepository.ps1 defaults to SSH deploy key mode and expects to find the key
    this script provisions already in place, at the matching -KeyPath, it does not create
    one itself.
.PARAMETER Servers
    List servers comma-separated e.g. "eun047046.QAEUROPE.NOM,eun045838.qaeurope.nom"
.PARAMETER Repo
    The repository specified as, for example "eis-cyberark_password_vault-serverbuilds-eng/system-checks.git"
.PARAMETER ApiToken
    A GitLab project access token with the "api" scope and at least the Maintainer role,
    used once per host to register that host's public key as a deploy key. Not stored
    anywhere after this run. If omitted, the script explains how to create one on
    gitlab.company.com and prompts for it interactively.
.PARAMETER GitLabHost
    The GitLab hostname used for the API call and the SSH verification. Defaults to
    "gitlab.company.com".
.PARAMETER KeyPath
    The private key path on each target host. Each repository gets its own keypair, even
    on the same host, so this defaults to a path derived from -Repo,
    "C:\ProgramData\ssh\gitlab_deploy_<repo-slug>_ed25519", rather than one shared file.
    Override it only if you need a specific path.
.PARAMETER AllowPush
    Registers the deploy key with write access. This is the split between the two ways
    this key gets used: operations hosts that only ever deploy from GitLab should omit
    this, they get a read-only key and can never push local changes back, any repository
    change has to go through gitlab.company.com directly. Engineer hosts that need full
    git access, commits, pushes, pulls, working through an editor, need this switch so
    their key can push.
.PARAMETER SkipCredentialCleanup
    By default, before provisioning the new deploy key, each host has its existing SSH
    private keys under the connecting account's profile removed, any loaded ssh-agent
    identities cleared, matching GitLab entries removed from Windows Credential Manager,
    and the global git credential.helper unset. Pass this switch to skip that cleanup.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter comma separated server list")]
    [string]$Servers,
    [Parameter(Mandatory = $true,
        HelpMessage = "Provide the git destination e.g. " +
            "eis-cyberark_password_vault-serverbuilds-eng/system-checks.git")]
    [string]$Repo,
    [System.Security.SecureString]$ApiToken,
    [string]$GitLabHost = "gitlab.company.com",
    [string]$KeyPath,
    [switch]$AllowPush,
    [switch]$SkipCredentialCleanup
)

# Enforce TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($PSBoundParameters.Count -eq 0) {
    Write-Warning "At least one parameter must be specified:"
    Write-Warning "[-Servers]    - Server list to provision, comma separated"
    Write-Warning "[-Repo]       - Git Repository"
    Write-Warning "[-ApiToken]   - GitLab API token (SecureString). Omit it to be guided through creating one"
    Write-Warning "[-GitLabHost] - GitLab hostname, defaults to gitlab.company.com"
    Write-Warning "[-KeyPath]    - Private key path on each host"
    Write-Warning "[-AllowPush]  - Register a read-write key instead of read-only"
    Write-Warning "[-SkipCredentialCleanup] - Skip removing existing SSH keys and cached credentials"
    exit 1
}

# Enable Debug, overriding the default Inquire behaviour so -Debug prints rather than
# prompts. This also lets the preference be threaded into each remote session below
$Splat = @{}
$DebugPreference = 'SilentlyContinue'
if ($PSBoundParameters['Debug'] -and $PSBoundParameters.Debug) {
    $DebugPreference = 'Continue'
    $Splat['Debug'] = $true
}

# Enable Verbose
if ($PSBoundParameters['Verbose'] -and $PSBoundParameters.Verbose) {
    Write-Output "INFO: Verbose enabled"
    $Splat['Verbose'] = $true
}

function ConvertFrom-SecureStringToPlainText {
    [CmdletBinding()]
    param([System.Security.SecureString]$SecureString)

    $Bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($Bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
    }
}

# The project path GitLab's API needs, with the .git suffix stripped and the slash encoded
$ProjectPath    = $Repo -replace '\.git$', ''
$EncodedProject = [uri]::EscapeDataString($ProjectPath)

# Each repository gets its own keypair, even on the same host, so the default path is
# derived from the repo rather than being one shared file every project would collide on
if (-not $PSBoundParameters.ContainsKey('KeyPath')) {
    $RepoSlug = $ProjectPath -replace '[\\/]', '_'
    $KeyPath  = "C:\ProgramData\ssh\gitlab_deploy_${RepoSlug}_ed25519"
}

if (-not $PSBoundParameters.ContainsKey('ApiToken')) {
    Write-Output "INFO: A GitLab access token is needed to register each host's deploy key."
    Write-Output "INFO: It is used once per host, held in memory only, then discarded. Create one now:"
    Write-Output "INFO:   1. Sign in to https://$GitLabHost and open the project $ProjectPath"
    Write-Output "INFO:   2. Go to Settings, then Access Tokens"
    Write-Output "INFO:   3. Under 'Add new token', set a short expiry date"
    Write-Output "INFO:   4. Select only the 'api' scope, nothing else"
    Write-Output "INFO:   5. Set the role to at least Maintainer, deploy key registration needs it"
    Write-Output "INFO:   6. Click 'Create project access token' and copy the value now, GitLab shows it once"
    $ApiToken = Read-Host -AsSecureString -Prompt "Paste the GitLab API token here"
}

if ((-not $ApiToken) -or ($ApiToken.Length -eq 0)) {
    Write-Warning "A GitLab API token is required to continue."
    exit 1
}

# Decrypted once, in memory only, then handed to each remote session over WinRM's
# already-encrypted transport, the same pattern the deployment script already uses
$PlainApiToken = ConvertFrom-SecureStringToPlainText -SecureString $ApiToken

$HostList     = $Servers -split "," | ForEach-Object { $_.Trim() }
$FailureCount = 0

Write-Output "INFO: Server list  : $HostList"
Write-Output "INFO: Repository   : $ProjectPath"
Write-Output "INFO: GitLab host  : $GitLabHost"
Write-Output "INFO: Key path     : $KeyPath"
Write-Output "INFO: Access level : $(if ($AllowPush) { 'read-write' } else { 'read-only' })"
Write-Debug "Repository path encoded for the API as: $EncodedProject"
Write-Debug "Deploy key API endpoint will be: https://$GitLabHost/api/v4/projects/$EncodedProject/deploy_keys"

foreach ($Target in $HostList) {
    Write-Debug "Debug connection to $Target"
    $WinRMTest = Test-WSMan -ComputerName $Target -ErrorAction SilentlyContinue
    if ($null -eq $WinRMTest) {
        Write-Warning "WinRM is not available on '$Target'."
        $FailureCount++
        continue
    }

    $InvokeParams = @{
        ComputerName = $Target
        ArgumentList = @($KeyPath, $EncodedProject, $PlainApiToken, $GitLabHost, [bool]$AllowPush,
            [bool]$SkipCredentialCleanup)
        ScriptBlock  = {
            param($KeyPath, $EncodedProject, $PlainApiToken, $GitLabHost, $AllowPush, $SkipCredentialCleanup)

            $DebugPreference = 'SilentlyContinue'
            if ($using:DebugPreference -eq 'Continue') {
                $DebugPreference = 'Continue'  # Debug now enabled within invoke-command
            }

            Write-Output "INFO: $env:COMPUTERNAME - Provisioning GitLab deploy key"
            Write-Debug "$env:COMPUTERNAME - Key path: $KeyPath"
            Write-Debug "$env:COMPUTERNAME - Encoded project: $EncodedProject"
            Write-Debug "$env:COMPUTERNAME - GitLab host: $GitLabHost"

            # Only trust a path already on PATH or a handful of common Git for Windows
            # install locations, never assume one fixed layout, installs vary by host
            $GitFound = [bool](Get-Command git.exe -ErrorAction SilentlyContinue)
            if (-not $GitFound) {
                $GitCandidates = @(
                    "C:\Program Files\Git\cmd",
                    "C:\Program Files\Git\bin",
                    "C:\Program Files\Git\mingw64\bin",
                    "C:\Program Files\Git\usr\bin",
                    "C:\Program Files (x86)\Git\cmd",
                    "C:\Program Files (x86)\Git\bin"
                )
                foreach ($GitCandidate in $GitCandidates) {
                    if (Test-Path (Join-Path $GitCandidate "git.exe")) {
                        $env:Path = "$GitCandidate;" + $env:Path
                        $GitFound = $true
                        break
                    }
                }
            }
            if (-not $GitFound) {
                Write-Warning ("$env:COMPUTERNAME - git.exe not found on PATH or in any common " +
                    "Git for Windows install location. Install it or add it to PATH on this host.")
                return $false
            }

            if (-not (Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue)) {
                Write-Warning "$env:COMPUTERNAME OpenSSH client not installed. Skipping"
                return $false
            }

            if (-not $SkipCredentialCleanup) {
                Write-Output "INFO: $env:COMPUTERNAME - Removing existing SSH keys and cached git credentials"

                $KeyHeaders  = "BEGIN OPENSSH PRIVATE KEY", "BEGIN RSA PRIVATE KEY",
                    "BEGIN DSA PRIVATE KEY", "BEGIN EC PRIVATE KEY"
                $SshFiles    = Get-ChildItem "$HOME\.ssh" -File -Force -ErrorAction SilentlyContinue
                $OldKeyFiles = $SshFiles | Where-Object {
                    $FirstLine = Get-Content $_.FullName -TotalCount 1 -ErrorAction SilentlyContinue
                    $KeyHeaders | Where-Object { $FirstLine -match $_ }
                }

                foreach ($OldKeyFile in $OldKeyFiles) {
                    Write-Output "INFO: $env:COMPUTERNAME - Removing existing key $($OldKeyFile.FullName)"
                    Remove-Item $OldKeyFile.FullName -Force
                    $OldPubFile = "$($OldKeyFile.FullName).pub"
                    if (Test-Path $OldPubFile) {
                        Remove-Item $OldPubFile -Force
                    }
                }

                if (Get-Command ssh-add.exe -ErrorAction SilentlyContinue) {
                    & ssh-add.exe -D 2>&1 | Out-Null
                }

                $StoredCredentials = & cmdkey.exe /list | Select-String -Pattern "gitlab" -SimpleMatch
                foreach ($StoredCredential in $StoredCredentials) {
                    if ($StoredCredential -match "Target:\s*(\S+)") {
                        $CredentialTarget = $Matches[1]
                        Write-Output "INFO: $env:COMPUTERNAME - Removing stored credential $CredentialTarget"
                        & cmdkey.exe /delete:$CredentialTarget | Out-Null
                    }
                }

                $GlobalHelper = & git config --global --get credential.helper 2>$null
                if ($GlobalHelper) {
                    Write-Output "INFO: $env:COMPUTERNAME - Clearing global git credential.helper ($GlobalHelper)"
                    & git config --global --unset credential.helper
                }
            }

            $KeyDir         = Split-Path -Path $KeyPath -Parent
            $CurrentAccount = "$env:USERDOMAIN\$env:USERNAME"
            if (-not (Test-Path $KeyDir)) {
                New-Item -ItemType Directory -Path $KeyDir -Force | Out-Null
            }

            # Lock the folder down before anything is written into it, so a newly created
            # key never inherits a broader permission set from its parent, even briefly
            & icacls.exe $KeyDir /inheritance:r | Out-Null
            & icacls.exe $KeyDir /grant:r "SYSTEM:(OI)(CI)F" | Out-Null
            & icacls.exe $KeyDir /grant:r "BUILTIN\Administrators:(OI)(CI)F" | Out-Null
            & icacls.exe $KeyDir /grant:r "${CurrentAccount}:(OI)(CI)R" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "$env:COMPUTERNAME - Failed to set ACLs on $KeyDir"
                return $false
            }

            if (-not (Test-Path $KeyPath)) {
                & ssh-keygen.exe -t ed25519 -f $KeyPath -N '""' -C "deploy-$env:COMPUTERNAME" | Out-Null
                if ($LASTEXITCODE -ne 0) {
                    Write-Warning "$env:COMPUTERNAME - ssh-keygen failed with exit code $LASTEXITCODE"
                    return $false
                }
            } else {
                Write-Output "INFO: $env:COMPUTERNAME - Key already exists at $KeyPath, reusing it"
            }

            # Re-assert explicit permissions on the file itself as defense in depth, on top
            # of the folder-level lockdown above
            & icacls.exe $KeyPath /inheritance:r | Out-Null
            & icacls.exe $KeyPath /grant:r "SYSTEM:(F)" | Out-Null
            & icacls.exe $KeyPath /grant:r "BUILTIN\Administrators:(F)" | Out-Null
            & icacls.exe $KeyPath /grant:r "${CurrentAccount}:(R)" | Out-Null
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "$env:COMPUTERNAME - Failed to set ACLs on private key"
                return $false
            }

            $PublicKey = (Get-Content "$KeyPath.pub" -Raw).Trim()

            $ApiUri  = "https://$GitLabHost/api/v4/projects/$EncodedProject/deploy_keys"
            $ApiBody = @{
                title    = "deploy-$env:COMPUTERNAME"
                key      = $PublicKey
                can_push = $AllowPush
            } | ConvertTo-Json

            $RestParams = @{
                Method      = "Post"
                Uri         = $ApiUri
                Headers     = @{ "PRIVATE-TOKEN" = $PlainApiToken }
                Body        = $ApiBody
                ContentType = "application/json"
            }

            Write-Debug "$env:COMPUTERNAME - POST $ApiUri"
            Write-Debug "$env:COMPUTERNAME - Body: $ApiBody"

            try {
                $null = Invoke-RestMethod @RestParams
                Write-Output "INFO: $env:COMPUTERNAME - Deploy key registered on $EncodedProject"
            } catch {
                # Invoke-RestMethod only exposes GitLab's actual reason, wrong project path,
                # no access, wrong host, through the response body, not the generic .NET
                # exception message, so read that body before deciding what happened
                $ErrorMessage = $_.Exception.Message
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                    $ErrorMessage = $_.ErrorDetails.Message
                } elseif ($_.Exception.Response) {
                    try {
                        $ResponseStream = $_.Exception.Response.GetResponseStream()
                        $StreamReader   = New-Object System.IO.StreamReader($ResponseStream)
                        $ResponseBody   = $StreamReader.ReadToEnd()
                        $StreamReader.Close()
                        if ($ResponseBody) {
                            $ErrorMessage = $ResponseBody
                        }
                    } catch {
                        # Response body was not readable, fall back to the exception message above
                    }
                }

                $AlreadyRegistered = $ErrorMessage -match "fingerprint.*taken"
                if ($AlreadyRegistered) {
                    Write-Output "INFO: $env:COMPUTERNAME - Deploy key already registered, continuing"
                } else {
                    Write-Warning "$env:COMPUTERNAME - Deploy key registration failed: $ErrorMessage"
                    Write-Warning ("$env:COMPUTERNAME - A 404 here usually means the project path is " +
                        "wrong, the token cannot see this project, or -GitLabHost points at the wrong " +
                        "instance, GitLab returns 404 for all three rather than distinguishing them.")
                    return $false
                }
            }

            # Verify the key actually authenticates. This relies on known_hosts already
            # holding a verified fingerprint for $GitLabHost, it will not auto-accept one.
            $VerifyOutput = & ssh.exe -i $KeyPath -o IdentitiesOnly=yes -o BatchMode=yes `
                -T "git@$GitLabHost" 2>&1 | Out-String
            $Verified = $VerifyOutput -match "Welcome to GitLab"

            if ($Verified) {
                Write-Output "INFO: $env:COMPUTERNAME - Deploy key verified against $GitLabHost"
            } else {
                Write-Warning "$env:COMPUTERNAME - Deploy key verification failed: $VerifyOutput"
            }

            return $Verified
        }
    }

    $HostProvisioned = Invoke-Command @InvokeParams
    if (-not $HostProvisioned) {
        $FailureCount++
    }
}

$PlainApiToken = $null

if ($FailureCount -gt 0) {
    Write-Warning "Provisioning finished with $FailureCount host failure(s)."
    exit 1
}

exit 0
