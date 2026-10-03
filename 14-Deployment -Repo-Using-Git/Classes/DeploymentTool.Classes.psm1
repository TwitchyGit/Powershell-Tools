<#
.SYNOPSIS
    Provides the object model and orchestration classes for repository refresh and setup.
#>

<#
.SYNOPSIS
    Provides shared objects used to keep deployment decisions explicit and testable.
#>

class DeploymentPackage {
    [string] $Name
    [string] $SourcePath
    [string] $Folder

    DeploymentPackage([string] $Name, [string] $SourcePath, [string] $Folder) {
        $this.Name = $Name
        $this.SourcePath = $SourcePath
        $this.Folder = $Folder
    }
}

class EnvironmentProfile {
    [string] $Name
    [string] $Branch
    [string] $PackageSource
    [bool] $RequiresSourceCredential
    [string] $VersionOne
    [string] $VersionTwo
    [string] $VersionThree
    [string] $BackupPool

    EnvironmentProfile(
        [string] $Name,
        [string] $Branch,
        [string] $PackageSource,
        [bool] $RequiresSourceCredential,
        [string] $VersionOne,
        [string] $VersionTwo,
        [string] $VersionThree,
        [string] $BackupPool
    ) {
        $this.Name = $Name
        $this.Branch = $Branch
        $this.PackageSource = $PackageSource
        $this.RequiresSourceCredential = $RequiresSourceCredential
        $this.VersionOne = $VersionOne
        $this.VersionTwo = $VersionTwo
        $this.VersionThree = $VersionThree
        $this.BackupPool = $BackupPool
    }
}

class OperationResult {
    [bool] $Succeeded
    [string[]] $Messages

    OperationResult([bool] $Succeeded, [string[]] $Messages) {
        $this.Succeeded = $Succeeded
        $this.Messages = $Messages
    }
}

class InputValidationResult {
    [bool] $IsValid
    [string[]] $Errors

    InputValidationResult([string[]] $Errors) {
        $this.Errors = $Errors
        $this.IsValid = ($Errors.Count -eq 0)
    }
}


class RepoRefreshEngine {
    [string[]] $Servers
    [string] $User
    [securestring] $Token
    [string] $Repo
    [string] $Dest
    [string] $Branch
    [string] $SourceRoot
    [bool] $IsRelaunched

    RepoRefreshEngine(
        [string[]] $Servers,
        [string] $User,
        [securestring] $Token,
        [string] $Repo,
        [string] $Dest,
        [string] $Branch,
        [string] $SourceRoot,
        [bool] $IsRelaunched
    ) {
        $this.Servers = $Servers
        $this.User = $User
        $this.Token = $Token
        $this.Repo = $Repo
        $this.Dest = $Dest
        $this.Branch = $Branch
        $this.SourceRoot = $SourceRoot
        $this.IsRelaunched = $IsRelaunched
    }

    [int] Run() {
        $Validation = $this.TestInput()
        if (-not $Validation.IsValid) {
            [Console]::Error.WriteLine(($Validation.Errors -join [Environment]::NewLine))
            return 1
        }

        if (-not $this.IsRelaunched) {
            return $this.InvokeRelaunchedCopy()
        }

        if (-not $this.TestSourceBranch()) {
            return 1
        }

        if (-not $this.TestHostsReady()) {
            return 1
        }

        $FailedHosts = [System.Collections.Generic.List[string]]::new()
        foreach ($Server in $this.Servers) {
            if (-not $this.InvokeHostReplacement($Server)) {
                $FailedHosts.Add($Server)
            }
        }

        $this.ClearSensitiveState()

        if ($FailedHosts.Count -gt 0) {
            [Console]::Error.WriteLine("Refresh failed on host: $($FailedHosts -join ', ').")
            return 1
        }

        Write-Output 'Refresh completed for every requested host.'
        return 0
    }

    [InputValidationResult] TestInput() {
        $Errors = [System.Collections.Generic.List[string]]::new()

        if ($null -eq $this.Servers -or $this.Servers.Count -eq 0) {
            $Errors.Add('At least one server is required.')
        } else {
            foreach ($Server in $this.Servers) {
                if ($Server -notmatch '^[A-Za-z0-9._-]+$') {
                    $Errors.Add("Server '$Server' contains invalid characters.")
                }
            }
        }

        if ($this.User -notmatch '^[A-Za-z0-9._-]+$') {
            $Errors.Add('User contains invalid characters.')
        }

        if ($this.Repo -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$' -or $this.Repo -match '\.\.') {
            $Errors.Add('Repo must be in group/project.git form with no parent-folder segments.')
        }

        if ($this.Branch -notmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*$' -or $this.Branch -match '\s') {
            $Errors.Add('Branch must start with a letter or digit and contain no spaces.')
        }

        if ($this.Dest -notmatch '^C:\\[A-Za-z0-9_ .\\-]+$' -or $this.Dest -match '\.\.') {
            $Errors.Add('Dest must be strictly below drive C with no parent-folder segments.')
        }

        if ($null -eq $this.Token -or $this.Token.Length -eq 0) {
            $Errors.Add('Token must not be empty.')
        }

        return [InputValidationResult]::new($Errors.ToArray())
    }

    [int] InvokeRelaunchedCopy() {
        $ScriptPath = $PSCommandPath
        $ProcessId = [System.Diagnostics.Process]::GetCurrentProcess().Id
        $TempName = "Invoke-RepoRefresh-$ProcessId-$([guid]::NewGuid()).ps1"
        $TempScript = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $TempName
        $ExportedToken = $null

        try {
            Copy-Item -Path $ScriptPath -Destination $TempScript -Force -ErrorAction Stop
            $ExportedToken = ConvertFrom-SecureString -SecureString $this.Token
            $ServerList = $this.Servers -join ','
            $Arguments = @(
                '-NoProfile',
                '-NonInteractive',
                '-File',
                $TempScript,
                '-Servers',
                $ServerList,
                '-User',
                $this.User,
                '-ProtectedToken',
                $ExportedToken,
                '-Repo',
                $this.Repo,
                '-Dest',
                $this.Dest,
                '-Branch',
                $this.Branch,
                '-SourceRoot',
                $this.SourceRoot,
                '-Relaunched'
            )

            $Process = Start-Process -FilePath 'pwsh' -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
            return $Process.ExitCode
        } catch {
            [Console]::Error.WriteLine("Relaunch failed: $($_.Exception.Message)")
            return 1
        } finally {
            if (Test-Path -Path $TempScript) {
                Remove-Item -Path $TempScript -Force -ErrorAction SilentlyContinue
            }
            $ExportedToken = $null
        }
    }

    [bool] TestSourceBranch() {
        $Address = $this.GetCredentialedAddress()
        $MaskedAddress = $this.GetMaskedAddress()

        try {
            $null = Get-Command -Name git -ErrorAction Stop
            $Arguments = @('ls-remote', '--heads', $Address, $this.Branch)
            $Output = & git @Arguments 2>&1
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace(($Output | Out-String))) {
                [Console]::Error.WriteLine("Branch '$($this.Branch)' was not found at $MaskedAddress.")
                return $false
            }
            return $true
        } catch {
            [Console]::Error.WriteLine("Source verification failed: $($_.Exception.Message)")
            return $false
        } finally {
            $Address = $null
        }
    }

    [bool] TestHostsReady() {
        $Failed = [System.Collections.Generic.List[string]]::new()

        foreach ($Server in $this.Servers) {
            try {
                if ($Server -eq $env:COMPUTERNAME -or $Server -eq 'localhost') {
                    $this.TestLocalHostReady()
                } else {
                    Invoke-Command -ComputerName $Server -ConfigurationName PowerShell.7 -ScriptBlock {
                        $null = Get-Command -Name git -ErrorAction Stop
                        Import-Module -Name 'RestartManager' -ErrorAction Stop
                    } -ErrorAction Stop
                }
            } catch {
                $Failed.Add("$Server ($($_.Exception.Message))")
            }
        }

        if ($Failed.Count -gt 0) {
            [Console]::Error.WriteLine("Host readiness failed: $($Failed -join '; ').")
            return $false
        }

        return $true
    }

    [void] TestLocalHostReady() {
        $null = Get-Command -Name git -ErrorAction Stop
        Import-Module -Name 'RestartManager' -ErrorAction Stop
    }

    [bool] InvokeHostReplacement([string] $Server) {
        if ($Server -eq $env:COMPUTERNAME -or $Server -eq 'localhost') {
            return $this.InvokeLocalReplacement($Server)
        }

        try {
            $Address = $this.GetCredentialedAddress()
            $Params = @{
                ComputerName = $Server
                ConfigurationName = 'PowerShell.7'
                ArgumentList = @($Address, $this.Dest, $this.Branch)
                ErrorAction = 'Stop'
                ScriptBlock = {
                    param(
                        [string] $CloneAddress,
                        [string] $Destination,
                        [string] $BranchName
                    )

                    $ArchiveName = "repo-backup-$([System.Diagnostics.Process]::GetCurrentProcess().Id).zip"
                    $Archive = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $ArchiveName
                    if (-not (Test-Path -Path $Destination)) {
                        Write-Error -Message "Package folder '$Destination' does not exist." -ErrorAction Stop
                    }

                    $ArchiveParams = @{
                        Path = Join-Path -Path $Destination -ChildPath '*'
                        DestinationPath = $Archive
                        Force = $true
                    }
                    Compress-Archive @ArchiveParams
                    Import-Module -Name 'RestartManager' -ErrorAction Stop
                    Remove-Item -Path $Destination -Recurse -Force -ErrorAction Stop
                    & git clone --single-branch --branch $BranchName $CloneAddress $Destination
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -Path $Destination)) {
                        if (Test-Path -Path $Destination) {
                            Remove-Item -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue
                        }
                        Expand-Archive -Path $Archive -DestinationPath $Destination -Force
                        Write-Error -Message 'Git fetch failed and previous contents were restored.' -ErrorAction Stop
                    }
                    Remove-Item -Path $Archive -Force -ErrorAction SilentlyContinue
                }
            }

            Invoke-Command @Params
            Write-Output "Refresh completed on $Server."
            return $true
        } catch {
            [Console]::Error.WriteLine("Refresh failed on ${Server}: $($_.Exception.Message)")
            return $false
        } finally {
            $Address = $null
        }
    }

    [bool] InvokeLocalReplacement([string] $Server) {
        $ArchiveName = "repo-backup-$([System.Diagnostics.Process]::GetCurrentProcess().Id).zip"
        $Archive = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath $ArchiveName
        $MoveAside = "$($this.Dest).old-$([System.Diagnostics.Process]::GetCurrentProcess().Id)"
        $Address = $this.GetCredentialedAddress()

        try {
            $null = Get-Command -Name git -ErrorAction Stop
            if (-not (Test-Path -Path $this.Dest)) {
                [Console]::Error.WriteLine("Package folder '$($this.Dest)' does not exist on $Server.")
                return $false
            }

            $ArchiveParams = @{
                Path = Join-Path -Path $this.Dest -ChildPath '*'
                DestinationPath = $Archive
                Force = $true
                ErrorAction = 'Stop'
            }
            Compress-Archive @ArchiveParams
            try {
                Import-Module -Name 'RestartManager' -ErrorAction Stop
            } catch {
                Write-Warning "Lock release helper was not loaded on ${Server}: $($_.Exception.Message)"
            }

            try {
                Remove-Item -Path $this.Dest -Recurse -Force -ErrorAction Stop
            } catch {
                Move-Item -Path $this.Dest -Destination $MoveAside -Force -ErrorAction Stop
            }

            & git clone --single-branch --branch $this.Branch $Address $this.Dest 2>&1 |
                ForEach-Object { $_ -replace [regex]::Escape($this.ConvertTokenToPlainText()), '<token>' }

            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -Path $this.Dest)) {
                if (Test-Path -Path $this.Dest) {
                    Remove-Item -Path $this.Dest -Recurse -Force -ErrorAction SilentlyContinue
                }
                Expand-Archive -Path $Archive -DestinationPath $this.Dest -Force -ErrorAction Stop
                [Console]::Error.WriteLine("Git fetch failed on $Server and previous contents were restored.")
                return $false
            }

            if (Test-Path -Path $MoveAside) {
                Remove-Item -Path $MoveAside -Recurse -Force -ErrorAction SilentlyContinue
            }
            Remove-Item -Path $Archive -Force -ErrorAction SilentlyContinue
            Write-Output "Refresh completed on $Server."
            return $true
        } catch {
            [Console]::Error.WriteLine("Refresh failed on ${Server}: $($_.Exception.Message)")
            if (Test-Path -Path $Archive -PathType Leaf) {
                if (Test-Path -Path $this.Dest) {
                    Remove-Item -Path $this.Dest -Recurse -Force -ErrorAction SilentlyContinue
                }
                Expand-Archive -Path $Archive -DestinationPath $this.Dest -Force -ErrorAction SilentlyContinue
            }
            return $false
        } finally {
            Remove-Item -Path $Archive -Force -ErrorAction SilentlyContinue
            $Address = $null
        }
    }

    [string] GetCredentialedAddress() {
        $PlainToken = $this.ConvertTokenToPlainText()
        return "$($this.SourceRoot.TrimEnd('/'))/$($this.User):$PlainToken@$($this.Repo)"
    }

    [string] GetMaskedAddress() {
        return "$($this.SourceRoot.TrimEnd('/'))/$($this.User):<token>@$($this.Repo)"
    }

    [string] ConvertTokenToPlainText() {
        $Pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($this.Token)
        try {
            return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($Pointer)
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Pointer)
        }
    }

    [void] ClearSensitiveState() {
        $this.Token = $null
    }
}


class DeploymentConfigurator {
    [EnvironmentProfile] $Profile
    [DeploymentPackage[]] $Packages
    [pscredential] $ServiceCredential
    [pscredential] $AdministratorCredential
    [string] $BackupServiceAccount

    DeploymentConfigurator(
        [EnvironmentProfile] $Profile,
        [DeploymentPackage[]] $Packages,
        [pscredential] $ServiceCredential,
        [pscredential] $AdministratorCredential,
        [string] $BackupServiceAccount
    ) {
        $this.Profile = $Profile
        $this.Packages = $Packages
        $this.ServiceCredential = $ServiceCredential
        $this.AdministratorCredential = $AdministratorCredential
        $this.BackupServiceAccount = $BackupServiceAccount
    }

    [int] Run() {
        $Recipes = $this.GetRecipes()
        $FailedFolders = [System.Collections.Generic.List[string]]::new()

        foreach ($Package in $this.Packages) {
            if (-not $Recipes.ContainsKey($Package.Name)) {
                [Console]::Error.WriteLine("No setup recipe exists for package '$($Package.Name)'.")
                $FailedFolders.Add($Package.Folder)
                continue
            }

            if (-not (Test-Path -Path $Package.Folder)) {
                Write-Warning "Package folder '$($Package.Folder)' does not exist. Setup skipped."
                continue
            }

            $Previous = Get-Location
            try {
                Set-Location -Path $Package.Folder
                $Recipe = $Recipes[$Package.Name]
                & $Recipe.Setup $Package $this.Profile $this.ServiceCredential $this.BackupServiceAccount
                if ($LASTEXITCODE -ne 0) {
                    Write-Error -Message "Setup action failed for '$($Package.Name)'." -ErrorAction Stop
                }

                if ($null -ne $Recipe.CredentialAction) {
                    try {
                        & $Recipe.CredentialAction $Package $this.ServiceCredential $this.AdministratorCredential
                    } catch {
                        Write-Warning "Credential action failed for '$($Package.Name)': $($_.Exception.Message)"
                    }
                }
            } catch {
                [Console]::Error.WriteLine("Setup failed for '$($Package.Name)': $($_.Exception.Message)")
                $FailedFolders.Add($Package.Folder)
            } finally {
                Set-Location -Path $Previous
            }
        }

        $this.ServiceCredential = $null
        $this.AdministratorCredential = $null

        if ($FailedFolders.Count -gt 0) {
            [Console]::Error.WriteLine("Setup failed for folder: $($FailedFolders -join ', ').")
            return 1
        }

        Write-Output 'Setup completed for every requested package.'
        return 0
    }

    [hashtable] GetRecipes() {
        return @{
            Repo1 = @{
                Setup = {
                    param($Package, $Profile, $ServiceCredential, $BackupServiceAccount)
                    $SetupScript = Join-Path -Path $Package.Folder -ChildPath 'Setup.ps1'
                    & $SetupScript -Credential $ServiceCredential -Version $Profile.VersionOne
                }
                CredentialAction = $null
            }
            Repo2 = @{
                Setup = {
                    param($Package, $Profile, $ServiceCredential, $BackupServiceAccount)
                    $SetupScript = Join-Path -Path $Package.Folder -ChildPath 'Setup.ps1'
                    & $SetupScript -ServiceAccount $ServiceCredential.UserName
                }
                CredentialAction = $null
            }
            Repo3 = @{
                Setup = {
                    param($Package, $Profile, $ServiceCredential, $BackupServiceAccount)
                    $SetupScript = Join-Path -Path $Package.Folder -ChildPath 'Setup.ps1'
                    & $SetupScript -ServiceAccount $ServiceCredential.UserName
                }
                CredentialAction = {
                    param($Package, $ServiceCredential, $AdministratorCredential)
                    $CredentialParams = @{
                        ComputerName = 'localhost'
                        Credential = $ServiceCredential
                        ScriptBlock = {
                        param($AdminUser)
                        Write-Output "Credential vault update requested by $AdminUser."
                        }
                        ArgumentList = $AdministratorCredential.UserName
                    }
                    Invoke-Command @CredentialParams
                }
            }
            Repo4 = @{
                Setup = {
                    param($Package, $Profile, $ServiceCredential, $BackupServiceAccount)
                    $SetupScript = Join-Path -Path $Package.Folder -ChildPath 'Setup.ps1'
                    & $SetupScript -ServiceAccount $BackupServiceAccount -Version $Profile.VersionTwo
                }
                CredentialAction = {
                    param($Package, $ServiceCredential, $AdministratorCredential)
                    $CredentialParams = @{
                        ComputerName = 'localhost'
                        Credential = $ServiceCredential
                        ScriptBlock = {
                        param($AdminUser)
                        Write-Output "Credential vault update requested by $AdminUser."
                        }
                        ArgumentList = $AdministratorCredential.UserName
                    }
                    Invoke-Command @CredentialParams
                }
            }
            Repo5 = @{
                Setup = {
                    param($Package, $Profile, $ServiceCredential, $BackupServiceAccount)
                    $RemoveScript = Join-Path -Path $Package.Folder -ChildPath 'Remove-Replication.ps1'
                    if (Test-Path -Path $RemoveScript) {
                        & $RemoveScript
                    }
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error -Message 'Replication removal failed.' -ErrorAction Stop
                    }
                    & (Join-Path -Path $Package.Folder -ChildPath 'Setup.ps1') `
                        -ServiceAccount $BackupServiceAccount `
                        -Version $Profile.VersionThree `
                        -BackupPool $Profile.BackupPool
                    if ($LASTEXITCODE -eq 0) {
                        New-EventLog -LogName Application -Source $Package.Name -ErrorAction SilentlyContinue
                    }
                }
                CredentialAction = {
                    param($Package, $ServiceCredential, $AdministratorCredential)
                    $CredentialParams = @{
                        ComputerName = 'localhost'
                        Credential = $ServiceCredential
                        ScriptBlock = {
                        param($AdminUser)
                        Write-Output "Credential vault update requested by $AdminUser."
                        }
                        ArgumentList = $AdministratorCredential.UserName
                    }
                    Invoke-Command @CredentialParams
                }
            }
        }
    }
}
