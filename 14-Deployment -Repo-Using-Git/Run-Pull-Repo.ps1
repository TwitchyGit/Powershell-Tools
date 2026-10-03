using module ./Classes/DeploymentTool.Classes.psm1
<#
.SYNOPSIS
    Collects refresh choices and calls the refresh engine once per selected package.
#>
[CmdletBinding()]
param(
    [ValidateSet('NONPROD', 'PROD')]
    [string] $Env,
    [string] $GitUser,
    [securestring] $GitToken,
    [string] $FailoverHost,
    [string[]] $RepoName,
    [switch] $RemoveToken,
    [string] $SourceRoot = 'https://source-control.example'
)

$Script:StartFolder = Get-Location
try {
    . "$PSScriptRoot\DeploymentSettings.ps1"

    if ([string]::IsNullOrWhiteSpace($Env)) {
        $Env = Read-Host -Prompt 'Environment (NONPROD, PROD)'
    }

    $Profile = Get-EnvironmentProfile -Env $Env
    $Packages = Get-CheckedCatalogue -RepoName $RepoName

    if ($Profile.RequiresSourceCredential) {
        if ([string]::IsNullOrWhiteSpace($GitUser)) {
            $GitUser = Read-Host -Prompt 'Source-control account'
        }
        if ($null -eq $GitToken) {
            $GitToken = Read-Host -Prompt 'Source-control token' -AsSecureString
        }
    } else {
        $GitUser = 'anonymous'
        $GitToken = ConvertTo-SecureString -String 'unused' -AsPlainText -Force
    }

    if ($null -eq $FailoverHost) {
        $FailoverHost = Read-Host -Prompt 'Secondary hosts, comma-separated, blank for local only'
    }

    $Servers = @('localhost')
    if (-not [string]::IsNullOrWhiteSpace($FailoverHost)) {
        $Servers += $FailoverHost.Split(',') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    }

    Write-Output "Environment: $($Profile.Name)"
    Write-Output "Branch: $($Profile.Branch)"
    Write-Output "Package source: $($Profile.PackageSource)"
    Write-Output "Hosts: $($Servers -join ', ')"
    Write-Output "Packages: $(($Packages.Name) -join ', ')"
    $null = Read-Host -Prompt 'Press return to continue'

    $null = Get-Command -Name git -ErrorAction Stop

    foreach ($Package in $Packages) {
        if (-not (Test-Path -Path $Package.Folder)) {
            Write-Warning "Package folder '$($Package.Folder)' does not exist. Refresh skipped."
            continue
        }

        Write-Output "Uncommitted report for $($Package.Name) at $($Package.Folder):"
        Push-Location -Path $Package.Folder
        try {
            & git status --short
        } finally {
            Pop-Location
        }
    }

    $null = Read-Host -Prompt 'Commit changes by hand or accept they will be lost, then press return'

    foreach ($Package in $Packages) {
        if (-not (Test-Path -Path $Package.Folder)) {
            Write-Warning "Package folder '$($Package.Folder)' does not exist. Refresh skipped."
            continue
        }

        $EnginePath = Join-Path -Path $PSScriptRoot -ChildPath 'Invoke-RepoRefresh.ps1'
        & $EnginePath `
            -Servers ($Servers -join ',') `
            -User $GitUser `
            -Token $GitToken `
            -Repo $Package.SourcePath `
            -Dest $Package.Folder `
            -Branch $Profile.Branch `
            -SourceRoot $SourceRoot

        if ($LASTEXITCODE -ne 0) {
            Write-Error -Message "Refresh failed for '$($Package.Name)'."
            exit 1
        }

        $Acl = Get-Acl -Path $Package.Folder
        $Rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            [System.Security.Principal.WindowsIdentity]::GetCurrent().Name,
            'FullControl',
            'ContainerInherit,ObjectInherit',
            'None',
            'Allow'
        )
        $Acl.SetAccessRule($Rule)
        Set-Acl -Path $Package.Folder -AclObject $Acl

        if ($RemoveToken.IsPresent) {
            Push-Location -Path $Package.Folder
            try {
                & git remote set-url origin "$($SourceRoot.TrimEnd('/'))/$($Package.SourcePath)"
            } finally {
                Pop-Location
            }
        }
    }

    exit 0
} catch {
    Write-Error -Message "Launcher stopped: $($_.Exception.Message)"
    exit 1
} finally {
    Set-Location -Path $Script:StartFolder
}
