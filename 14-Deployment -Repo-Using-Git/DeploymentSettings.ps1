<#
.SYNOPSIS
    Holds the package catalogue and per-environment values, and provides the routine that applies setup to each
    package
#>

$Deployments = @(
    @{ RepoName = "Repo1"; Repo = "reponame/deployment1.git"; Dest = "D:\Deployment1" }
    @{ RepoName = "Repo2"; Repo = "reponame/deployment2.git"; Dest = "D:\Deployment2" }
    @{ RepoName = "Repo3"; Repo = "reponame/deployment3.git"; Dest = "D:\Deployment3" }
    @{ RepoName = "Repo4"; Repo = "reponame/deployment4.git"; Dest = "D:\Deployment4" }
    @{ RepoName = "Repo5"; Repo = "reponame/deployment5.git"; Dest = "D:\Deployment5" }
)

$Script:EnvSettings = @{
    ENG    = @{
        PACLIVersion = 'v14.6'
        PADRVersion  = 'v14.6'
        EVDVersion   = 'v14.6.5.302'
        BackupPool   = 'DR_Pool_ENG1'
    }
    DEV    = @{
        PACLIVersion = 'v14.6'
        PADRVersion  = 'v14.6'
        EVDVersion   = 'v14.6.5.302'
        BackupPool   = 'DR_Pool_DEV1'
    }
    PROD    = @{
        PACLIVersion = 'v14.2'
        PADRVersion  = 'v14.2'
        EVDVersion   = 'v14.2.4.220'
        BackupPool   = 'DR_Pool_Prod1'
    }
}

<#
.SYNOPSIS
    Gives one place to read the per-environment tool versions and backup pool, so every package is configured
    from the same values.
#>
function Get-EnvSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('ENG', 'DEV', 'PROD')][string]$Env
    )

    $Script:EnvSettings[$Env]
}

<#
.SYNOPSIS
    Checks the package catalogue and the requested -RepoName values up front, so a typo or bad entry stops the run
    before anything is configured.
#>
function Resolve-RepoDeployment {
    [CmdletBinding()]
    param(
        [string[]]$RepoName
    )

    $ValidationErrors = [System.Collections.Generic.List[string]]::new()
    $KnownNames = @{}
    foreach ($Deployment in $Deployments) {
        $Name = $Deployment.RepoName
        if ([string]::IsNullOrWhiteSpace($Name)) {
            $ValidationErrors.Add("A deployment has no RepoName (Repo: $($Deployment.Repo))")
        } elseif ($KnownNames.ContainsKey($Name)) {
            $ValidationErrors.Add("Duplicate RepoName '$Name'")
        } else {
            $KnownNames[$Name] = $true
        }

        $RepoValid = $Deployment.Repo -match '^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)+$' -and
            $Deployment.Repo -notmatch '\.\.'
        if (-not $RepoValid) {
            $ValidationErrors.Add("Deployment '$Name' has an invalid Repo '$($Deployment.Repo)'")
        }

        $DestInvalid = $Deployment.Dest -notmatch '^[Dd]:\\[A-Za-z0-9._ \\-]+$' -or $Deployment.Dest -match '^[Dd]:\\*$'
        if ($DestInvalid -or ($Deployment.Dest -split '[\\/]') -contains '..') {
            $ValidationErrors.Add("Deployment '$Name' has an invalid Dest '$($Deployment.Dest)'")
        }
    }
    if ($ValidationErrors.Count -gt 0) {
        Write-Error -Message ($ValidationErrors -join "`n") -ErrorAction Stop
    }

    $Requested = @(
        $RepoName |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
    if ($Requested.Count -eq 0) {
        return @($Deployments)
    }

    $Unknown = @($Requested | Where-Object { -not $KnownNames.ContainsKey($_) })
    if ($Unknown.Count -gt 0) {
        Write-Error -Message ("Unknown RepoName: $($Unknown -join ', '). " +
            "Valid names: $(($Deployments | ForEach-Object { $_.RepoName }) -join ', ')") -ErrorAction Stop
    }

    return @($Deployments | Where-Object { $_.RepoName -in $Requested })
}

<#
.SYNOPSIS
    Runs a command as the service account with a full logon, so network resources are reachable without
    second-hop delegation.
#>
function Invoke-AsServiceAccount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][PSCredential]$ServiceCredential,
        [Parameter(Mandatory)][PSCredential]$AdminUser,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string]$CommandText
    )

    # The admin credential travels on stdin so it never appears on a command line, in the environment or on disk
    $Script = @'
$ErrorActionPreference = 'Stop'
$AdminName  = [Console]::In.ReadLine()
$AdminPlain = [Console]::In.ReadLine()
$AdminUser  = [pscredential]::new($AdminName, (ConvertTo-SecureString -String $AdminPlain -AsPlainText -Force))
$AdminPlain = $null
$global:LASTEXITCODE = 0
try {
__COMMAND__
    exit [int]$LASTEXITCODE
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
'@.Replace('__COMMAND__', $CommandText)

    # DOMAIN\account is split because Secondary Logon takes the domain separately, a UPN is passed whole
    $UserName = $ServiceCredential.UserName
    $Domain   = $null
    if ($UserName -match '^(?<Domain>[^\\]+)\\(?<Name>.+)$') {
        $Domain   = $Matches.Domain
        $UserName = $Matches.Name
    } elseif ($UserName -notmatch '^[^@\\\s]+@[^@\\\s]+$') {
        Write-Error -Message "Service account must be DOMAIN\account or account@domain. Value was '$UserName'" `
            -ErrorAction Stop
    }

    # CreateProcessWithLogonW caps the command line at 1024 characters, so the script goes in a file instead
    # C:\Temp is readable by the service account, unlike the elevated user's own temp folder
    $ScriptDirectory = 'C:\Temp'
    if (-not (Test-Path -LiteralPath $ScriptDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $ScriptDirectory -Force
    }
    $ScriptPath = Join-Path -Path $ScriptDirectory -ChildPath ("configure_" + [guid]::NewGuid() + ".ps1")
    Set-Content -LiteralPath $ScriptPath -Value $Script

    $StartInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $StartInfo.FileName = Join-Path -Path $PSHOME -ChildPath 'pwsh.exe'
    foreach ($Argument in '-NoProfile', '-NonInteractive', '-File', $ScriptPath) {
        $StartInfo.ArgumentList.Add($Argument)
    }
    $StartInfo.UserName               = $UserName
    if ($Domain) {
        $StartInfo.Domain = $Domain
    }
    $StartInfo.Password              = $ServiceCredential.Password.Copy()
    $StartInfo.LoadUserProfile        = $true
    $StartInfo.WorkingDirectory       = $WorkingDirectory
    $StartInfo.UseShellExecute        = $false
    $StartInfo.CreateNoWindow         = $true
    $StartInfo.RedirectStandardInput  = $true
    $StartInfo.RedirectStandardOutput = $true
    $StartInfo.RedirectStandardError  = $true

    $Process = $null
    try {
        $Process = [System.Diagnostics.Process]::Start($StartInfo)
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask  = $Process.StandardError.ReadToEndAsync()
        $Process.StandardInput.WriteLine($AdminUser.UserName)
        $Process.StandardInput.WriteLine($AdminUser.GetNetworkCredential().Password)
        $Process.StandardInput.Close()
        $Process.WaitForExit()
        [pscustomobject]@{
            ExitCode = $Process.ExitCode
            Output   = ($OutputTask.Result + $ErrorTask.Result)
        }
    } finally {
        if ($Process) {
            $Process.Dispose()
        }
        $StartInfo.Password.Dispose()
        Remove-Item -LiteralPath $ScriptPath -Force -ErrorAction SilentlyContinue
    }
}

<#
.SYNOPSIS
    Applies each selected package's configuration and credential setup under the service account so the
    refreshed packages run with the right identity.
#>
function Invoke-Configure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('ENG', 'DEV', 'PROD')][string]$Env,
        [Parameter(Mandatory)]$ServiceAccount,
        [Parameter(Mandatory)]$ServiceAccountBackup,
        [Parameter(Mandatory)]$ServiceCredential,
        [Parameter(Mandatory)]$AdminUser,
        [string[]]$RepoName
    )

    $Settings = Get-EnvSettings -Env $Env

    # Scriptblocks resolve variables when invoked, so they must run inside this function.
    $Configure = @(
        @{
            RepoName = "Repo1"
            Dest    = 'D:\Deployment1\Install'
            SetConfig = {
                # Repo1 gets the whole PSCredential (full DOMAIN\account or UPN), Repos 2-5 get the bare account name
                $Params = @{
                    Env            = $Env
                    ServiceAccount = $ServiceCredential
                    PACLIVersion   = $Settings.PACLIVersion
                }
                .\Set-Configuration.ps1 @Params
            }
        }
        @{
            RepoName = "Repo2"
            Dest    = 'D:\Deployment2\Install'
            SetConfig = { .\Set-Configuration.ps1 -Env $Env -ServiceAccount $ServiceAccount }
        }
        @{
            RepoName = "Repo3"
            Dest    = 'D:\Deployment3\Install'
            SetConfig = { .\Set-Configuration.ps1 -Env $Env -ServiceAccount $ServiceAccount }
            SetCred = { .\Create-Credentials.ps1 -AdminUser $AdminUser }
        }
        @{
            RepoName = "Repo4"
            Dest    = 'D:\Deployment4\Install'
            SetConfig = {
                $Params = @{
                    Env            = $Env
                    ServiceAccount = $ServiceAccountBackup
                    EVDVersion     = $Settings.EVDVersion
                }
                .\Set-Configuration.ps1 @Params
            }
            SetCred = { .\Create-Credentials.ps1 -AdminUser $AdminUser }
        }
        @{
            RepoName = "Repo5"
            Dest    = 'D:\Deployment5\Install'
            SetConfig = {
                .\Uninstall-Replicator.ps1 -ProgramName 'Replicator'
                if ($LASTEXITCODE -eq 0) {
                    $Params = @{
                        Env            = $Env
                        ServiceAccount = $ServiceAccountBackup
                        Version        = $Settings.PADRVersion
                        BackupPoolName = $Settings.BackupPool
                    }
                    .\Set-Configuration.ps1 @Params
                    .\New-EventLog.ps1
                }
            }
            SetCred = { .\Create-Credentials.ps1 -AdminUser $AdminUser }
        }
    )

    $UnknownSteps = @($Configure | Where-Object { $_.RepoName -notin $Deployments.RepoName })
    if ($UnknownSteps.Count -gt 0) {
        Write-Error -Message ("Configure steps reference an unknown RepoName: " +
            "$(($UnknownSteps | ForEach-Object { $_.RepoName }) -join ', ')") -ErrorAction Stop
    }

    $SelectedNames = @(Resolve-RepoDeployment -RepoName $RepoName | ForEach-Object { $_.RepoName })
    $Configure = @($Configure | Where-Object { $_.RepoName -in $SelectedNames })

    $Failed = [System.Collections.Generic.List[string]]::new()

    foreach ($Step in $Configure) {
        $Dest = $Step.Dest
        $SetConfig = $Step.SetConfig
        $SetCred = $Step.SetCred

        if (-not (Test-Path -LiteralPath $Dest -PathType Container)) {
            Write-Warning "$Dest directory does not exist, please create only if the software needs to be installed"
            continue
        }

        Write-Output "`nINFO: Processing configuration steps for $Dest"

        Push-Location -LiteralPath $Dest
        $PreviousPreference = $ErrorActionPreference
        try {
            $global:LASTEXITCODE = 0
            $ErrorActionPreference = 'Stop'
            & $SetConfig
            $ExitCode = ($LASTEXITCODE -eq 0)
        } catch {
            Write-Error -Message "$Dest command failed: $($_.Exception.Message)" -ErrorAction Continue
            $ExitCode = $false
        } finally {
            $ErrorActionPreference = $PreviousPreference
        }

        if (-not $ExitCode) {
            $Failed.Add($Dest)
        }

        try {
            if ($ExitCode -and $SetCred) {
                # SetCred logs on as the full ServiceCredential, AdminUser arrives on stdin as entered
                try {
                    $RunParams = @{
                        ServiceCredential = $ServiceCredential
                        AdminUser         = $AdminUser
                        WorkingDirectory  = $Dest
                        CommandText       = $SetCred.ToString()
                    }
                    $Run = Invoke-AsServiceAccount @RunParams
                    Write-Output $Run.Output
                    if ($Run.ExitCode -ne 0) {
                        Write-Warning "Credential setup for $Dest exited with code $($Run.ExitCode)"
                        $Failed.Add($Dest)
                    }
                } catch {
                    Write-Output ("ERROR: Credential setup failed: $($_.Exception.GetType().FullName): " +
                        "$($_.Exception.Message) $($_.InvocationInfo.PositionMessage)")
                    $Failed.Add($Dest)
                }
            } elseif (-not $ExitCode) {
                Write-Warning "Skipped credential setup for $Dest as Set-Configuration.ps1 did not complete"
            }
        } finally {
            Pop-Location
        }
    }

    if ($Failed.Count -gt 0) {
        Write-Error -Message "Configuration failed for: $($Failed -join ', ')" -ErrorAction Stop
    }
}

Export-ModuleMember -Function Get-EnvSettings, Invoke-Configure, Resolve-RepoDeployment -Variable Deployments
