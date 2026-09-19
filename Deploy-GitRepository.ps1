# Note   : Admin access required for remote access to computers
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Git Repository deployment
.DESCRIPTION
    This deploys a git repository to multiple hosts over SSH, using the per-repository
    deploy key that Setup-GitRepoKeys.ps1 already provisioned on each host. Run that
    script against the same host list first, it provisions the key this script expects to
    find at -KeyPath and registers it with GitLab. This script never creates or registers
    a key itself, it only uses one that already exists. It fails clearly on any host where
    one is missing rather than falling back to some other credential.

    Whether a host can push back to GitLab depends entirely on how its key was registered,
    read-only for an operations host that only ever deploys from GitLab, meaning any change
    to the repository has to go through gitlab.company.com directly, or read-write for an
    engineer host that needs full git access, commits, pushes, pulls, working through an
    editor. That choice was made when Setup-GitRepoKeys.ps1 -AllowPush was, or was not,
    passed for that host, this script has no separate switch for it.
.LINK
    https://gitlab/eis-cyberark_password_vault-serverbuilds-eng/system-checks
.LINK
    https://confluence./ETCB/confluence/display/GTPSE/CyberArk+Upgrade+v14.x+-+System+Checks+Repository
.PARAMETER Servers
    List servers comma-separated e.g. "eun047046.QAEUROPE.NOM,eun045838.qaeurope.nom,eun045609.qaeurope.nom"
.PARAMETER Repo
    The repository specified as, for example "eis-cyberark_password_vault-serverbuilds-eng/system-checks.git"
.PARAMETER KeyPath
    The private key path to use on each host. Each repository gets its own keypair, even
    on the same host, so this defaults to a path derived from -Repo,
    "C:\ProgramData\ssh\gitlab_deploy_<repo-slug>_ed25519", matching the default
    Setup-GitRepoKeys.ps1 uses. Override it only if that script was run with a specific
    -KeyPath, in which case pass the same one here.
.PARAMETER GitLabHost
    The GitLab hostname. Defaults to "gitlab.company.com".
.PARAMETER Dest
    The directory to clear and deploy the software to, for example "D:\System-Checks"
.PARAMETER Branch
    The git branch or tag to specify, for example "GPSESEC-1185" or "System-Checks_1.1"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter comma separated server list")]
    [string]$Servers = "localhost,localhost",
    [Parameter(Mandatory = $true,
        HelpMessage = "Provide the git destination e.g. " +
            "eis-cyberark_password_vault-serverbuilds-eng/system-checks.git")]
    [string]$Repo,
    [string]$KeyPath,
    [string]$GitLabHost = "gitlab.company.com",
    [Parameter(Mandatory = $true, HelpMessage = "Provide the target directory e.g. D:\System-Checks")]
    [string]$Dest,
    [Parameter(Mandatory = $true, HelpMessage = "Provide your git branch or tag")]
    [string]$Branch,
    [switch]$InternalTmpRun
)

# Enforce TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# No parameters listed
if ($PSBoundParameters.Count -eq 0) {
    Write-Warning "At least one parameter must be specified:"
    Write-Warning "[-Servers]    - Server list to deploy code to, comma separated"
    Write-Warning "[-Repo]       - Git Repository"
    Write-Warning "[-KeyPath]    - Private key path, defaults to one derived from -Repo"
    Write-Warning "[-GitLabHost] - GitLab hostname, defaults to gitlab.company.com"
    Write-Warning "[-Dest]       - Directory to export to e.g. D:\<name>"
    Write-Warning "[-Branch]     - Git Branch"
    Write-Warning "[-Verbose]    - Provide Debug information"
    exit 1
}

# Each repository gets its own keypair, even on the same host, so the default path is
# derived from the repo, matching Setup-GitRepoKeys.ps1's default, rather than one
# shared file every project would collide on
$ProjectPath = $Repo -replace '\.git$', ''
if (-not $PSBoundParameters.ContainsKey('KeyPath')) {
    $RepoSlug = $ProjectPath -replace '[\\/]', '_'
    $KeyPath  = "C:\ProgramData\ssh\gitlab_deploy_${RepoSlug}_ed25519"
}

# Initialize splat hashtable
$Splat = @{}

# Enable Debug
$DebugPreference = 'SilentlyContinue'
if ($PSBoundParameters['Debug'] -and $PSBoundParameters.Debug) {
    $DebugPreference = 'Continue'  # Show debug messages
    $Splat['Debug'] = $true
}

# Enable Verbose
if ($PSBoundParameters['Verbose'] -and $PSBoundParameters.Verbose) {
    Write-Output "INFO: Verbose enabled"
    $Splat['Verbose'] = $true
}

# Get location
$CurPWD = Get-Location

# Determine if verbose flag set
if ($Splat.ContainsKey('Verbose')) {
    Set-PSDebug -Trace 1
} else {
    Set-PSDebug -Trace 0
}

if (-not $InternalTmpRun) {
    # Ensure C:\Temp exists
    if (-not (Test-Path "C:\Temp")) {
        New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
    }

    # Copy myself to temporary location
    $ScriptPath  = $MyInvocation.MyCommand.Path
    $TmpFileName = "tmpfile_" + [guid]::NewGuid() + ".ps1"
    $TmpFile     = Join-Path "C:\Temp" $TmpFileName
    Copy-Item "$ScriptPath" -Destination $TmpFile

    # Build arg list to pass to Start-Process
    $ArgList = @(
        "-File",        $TmpFile,
        "-Servers",    "`"$Servers`"",
        "-Repo",       "`"$Repo`"",
        "-KeyPath",    "`"$KeyPath`"",
        "-GitLabHost", "`"$GitLabHost`"",
        "-Dest",       "`"$Dest`"",
        "-Branch",     "`"$Branch`"",
        "-InternalTmpRun"
    )
    if ($Splat.ContainsKey('Verbose')) {
        $ArgList += @( "-Verbose" )
    }
    if ($Splat.ContainsKey('Debug')) {
        $ArgList += @( "-Debug" )
    }

    # Reinvoke process in case we update ourselves
    Set-Location D:\

    try {
        Write-Debug "Running: powershell.exe $ArgList"
        $StartProcessParams = @{
            FilePath     = "powershell.exe"
            ArgumentList = $ArgList
            NoNewWindow  = $true
            Wait         = $true
            PassThru     = $true
            ErrorAction  = "Stop"
        }
        $Process   = Start-Process @StartProcessParams
        $ExitCode  = if ($Process.ExitCode -eq 0) { 0 } else { 1 }
    } catch {
        Write-Warning "Failed to start process: $($_.Exception.Message)"
        $ExitCode = 1
    }

    if (Test-Path $TmpFile) {
        Remove-Item $TmpFile -Force
    }

    # Set everything back
    Set-PSDebug -Trace 0
    Set-Location $CurPWD

    exit $ExitCode
}

$RepoUrl      = "git@${GitLabHost}:${Repo}"
$FailureCount = 0

# check directory
if (-not $Dest.ToUpper().StartsWith("D:\")) {
    Write-Warning "'$Dest' must start with D:\ - Value was '$Dest'"
    exit 1
}

# Construct host list
$HostList = $Servers -split "," | ForEach-Object { $_.Trim() }
Write-Output "INFO: Server list: $HostList"
Write-Output "INFO: Repository  : $RepoUrl"
Write-Output "INFO: Key path    : $KeyPath"
Write-Output "INFO: Branch      : $Branch"
Write-Output "INFO: Folder      : $Dest"
Write-Output "INFO: Each host must already have this key from Setup-GitRepoKeys.ps1"
Write-Output "INFO: Branch and connectivity are verified per host during clone, not upfront"

# Build git repository on each host
foreach ($Target in $HostList) {
    Write-Debug "Debug connection to $Target"
    $WinRMTest = Test-WSMan -ComputerName $Target -ErrorAction SilentlyContinue
    if ($null -eq $WinRMTest) {
        Write-Warning "WinRM is not available on '$Target'."
        $FailureCount++
        continue
    }

    try {
        $null = Invoke-Command -ComputerName $Target -ScriptBlock { $true }
    } catch {
        Write-Warning "Invoke-Command failed on '$Target'."
        $FailureCount++
        continue
    }

    $InvokeParams = @{
        ComputerName = $Target
        ArgumentList = @($RepoUrl, $Dest, $Branch, $KeyPath)
        ScriptBlock  = {
            param($RepoUrl, $Dest, $Branch, $KeyPath)

            $DebugPreference = 'SilentlyContinue'
            if ($using:DebugPreference -eq 'Continue') {
                $DebugPreference = 'Continue'  # Debug now enabled within invoke-command
                Set-PSDebug -Trace 1
            }

            Write-Output "INFO: $env:COMPUTERNAME - Setting up git repository"
            Write-Debug "$env:COMPUTERNAME - Repo URL: $RepoUrl"
            Write-Debug "$env:COMPUTERNAME - Key path: $KeyPath"
            Write-Debug "$env:COMPUTERNAME - Branch: $Branch, destination: $Dest"

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
                return $false  # Exit the script block for this host only
            }
            if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
                Write-Warning "$env:COMPUTERNAME OpenSSH client not installed. Skipping"
                return $false
            }
            if (-not (Test-Path $KeyPath)) {
                Write-Warning ("$env:COMPUTERNAME - No deploy key found at $KeyPath. " +
                    "Run Setup-GitRepoKeys.ps1 against this host first.")
                return $false
            }
            $env:GIT_SSH_COMMAND = "ssh -i `"$KeyPath`" -o IdentitiesOnly=yes -o BatchMode=yes"
            Write-Debug "$env:COMPUTERNAME - GIT_SSH_COMMAND: $env:GIT_SSH_COMMAND"

            # Move directories to prevent any conflict
            Push-Location "D:\"

            # Force create directory first, whether it exists or not, then cleanup contents
            if (-not (Test-Path -LiteralPath $Dest -PathType Container)) {
                try {
                    New-Item -Path "$Dest" -ItemType Directory -Force -ErrorAction Stop | Out-Null
                } catch {
                    Write-Warning "Failed to create directory '$Dest': $_"
                    return $false
                }
            }

            # Create temporary archive in case of locked files
            if (-not (Test-Path "C:\Temp")) {
                New-Item -ItemType Directory -Path "C:\Temp" -Force | Out-Null
            }

            $TmpZip = Join-Path "C:\Temp" ("tmpfile_" + [guid]::NewGuid() + ".zip")
            Push-Location "$Dest"
            $TmpSource = Get-ChildItem -Path . -Force
            if ($TmpSource) {
                Compress-Archive -Path $TmpSource -DestinationPath $TmpZip -Force
            }
            Pop-Location

            # Now try to remove destination and restore archive if something fails
            try {
                Remove-Item -Path $Dest -Recurse -Force -ErrorAction SilentlyContinue
                if (Test-Path $Dest) {
                    $TmpDir = Join-Path "C:\Temp" ("tmpdir_" + [guid]::NewGuid())
                    Move-Item $Dest -Destination $TmpDir -Force -ErrorAction Stop
                }
            } catch {
                Write-Warning "Unable to remove ${Dest}: $($_.Exception.Message)"
                if (Test-Path $TmpZip) {
                    Write-Warning "Attempting to restore files..."
                    Expand-Archive -Path $TmpZip -DestinationPath $Dest -Force
                    Remove-Item $TmpZip -Force -ErrorAction SilentlyContinue
                }

                if ($TmpDir -and (Test-Path $TmpDir)) {
                    Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
                }
                return $false  # This is correct, it exits the script block for this host only
            }

            if (Test-Path $TmpZip) {
                Remove-Item $TmpZip -Force -ErrorAction SilentlyContinue
            }
            if ($TmpDir -and (Test-Path $TmpDir)) {
                Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
            }

            $GitArgs = @(
                '-c'
                'core.fsmonitor=true'
                '-c'
                'advice.detachedHead=false'
                'clone'
                '--branch'
                $Branch
                '--single-branch'
                $RepoUrl
                $Dest
            )

            Write-Debug "$env:COMPUTERNAME - git clone args: $($GitArgs -join ' ')"

            $GitExit = 1
            try {
                $Result  = & git @GitArgs 2>&1
                $GitExit = $LASTEXITCODE

                if ($GitExit -ne 0) {
                    $GitOutput = $Result -join [Environment]::NewLine
                    Write-Warning "Git clone failed with exit code: $GitExit. `n$GitOutput"
                }
            } catch {
                Write-Warning "Git repository clone failed: $($_.Exception.Message)"
            }

            $Deployed = ($GitExit -eq 0) -and (Test-Path $Dest)
            if ($Deployed) {
                Write-Output "INFO: $env:COMPUTERNAME - Git repository deployed to folder $Dest"

                # Persist the key choice in the repo's own config, not just this session's
                # environment variable, so an engineer's later git commands or VS Code pick
                # up the right key automatically. This is a path, not a secret, safe to keep.
                & git -C $Dest config core.sshCommand "ssh -i `"$KeyPath`" -o IdentitiesOnly=yes"
            } else {
                Write-Output "$env:COMPUTERNAME $Dest folder has not been created"
            }

            Set-PSDebug -Trace 0

            return $Deployed
        }
    }
    $HostDeployed = Invoke-Command @InvokeParams
    if (-not $HostDeployed) {
        $FailureCount++
    }
}

Set-PSDebug -Trace 0
Set-Location $CurPWD

if ($FailureCount -gt 0) {
    Write-Warning "Deployment finished with $FailureCount host failure(s)."
    exit 1
}

exit 0
