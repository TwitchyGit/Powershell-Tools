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

function Get-EnvSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('ENG', 'DEV', 'PROD')][string]$Env
    )

    $Script:EnvSettings[$Env]
}

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

    # A -Credential remote session is a network logon with no onward credentials, so it fails on a second hop.
    # A RunAs endpoint gets a full logon as the service account instead.
    $EndpointName = $null
    try {
        if (@($Configure | Where-Object { $_.SetCred }).Count -gt 0) {
            $EndpointName = "ConfigureAsSvc_$PID"
            if (Get-PSSessionConfiguration -Name $EndpointName -ErrorAction SilentlyContinue) {
                Unregister-PSSessionConfiguration -Name $EndpointName -Force -ErrorAction Stop
            }
            # WinRM disposes the credential it is given, so register with a copy
            $RunAsCredential = [pscredential]::new($ServiceCredential.UserName, $ServiceCredential.Password.Copy())
            $null = Register-PSSessionConfiguration -Name $EndpointName -RunAsCredential $RunAsCredential `
                -Force -ErrorAction Stop
        }

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
                    $global:LASTEXITCODE = 0
                    try {
                        $AdminCopy = [pscredential]::new($AdminUser.UserName, $AdminUser.Password.Copy())
                        $Result = Invoke-Command -ComputerName localhost -ConfigurationName $EndpointName `
                            -ScriptBlock {
                                param($Dest, $AdminUser, $RunCommand)
                                Set-Location $Dest
                                & ([scriptblock]::Create($RunCommand)) 2>&1 | Out-String
                            } -ArgumentList $Dest, $AdminCopy, $SetCred -ErrorAction Stop
                        Write-Output $Result
                    } catch {
                        Write-Output ("ERROR: Invoke-Command failed: $($_.Exception.GetType().FullName): " +
                            "$($_.Exception.Message) $($_.InvocationInfo.PositionMessage)")
                    }
                } elseif (-not $ExitCode) {
                    Write-Warning "Skipped credential setup for $Dest as Set-Configuration.ps1 did not complete"
                }
            } finally {
                Pop-Location
            }
        }
    } finally {
        if ($EndpointName) {
            Unregister-PSSessionConfiguration -Name $EndpointName -Force -ErrorAction SilentlyContinue
        }
    }

    if ($Failed.Count -gt 0) {
        Write-Error -Message "Configuration failed for: $($Failed -join ', ')" -ErrorAction Stop
    }
}

Export-ModuleMember -Function Get-EnvSettings, Invoke-Configure, Resolve-RepoDeployment -Variable Deployments
