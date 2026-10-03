using module ./Classes/DeploymentTool.Classes.psm1
<#
.SYNOPSIS
    Replaces a package folder on the requested hosts with the selected source-control branch.
#>
[CmdletBinding()]
param(
    [string] $Servers,
    [string] $User,
    [securestring] $Token,
    [string] $ProtectedToken,
    [string] $Repo,
    [string] $Dest,
    [string] $Branch,
    [string] $SourceRoot = 'https://source-control.example',
    [switch] $Relaunched
)

$Script:StartFolder = Get-Location
try {
    . "$PSScriptRoot\DeploymentSettings.ps1"

    if ([string]::IsNullOrWhiteSpace($Servers) -or [string]::IsNullOrWhiteSpace($User) -or `
        ([string]::IsNullOrWhiteSpace($ProtectedToken) -and $null -eq $Token) -or `
        [string]::IsNullOrWhiteSpace($Repo) -or [string]::IsNullOrWhiteSpace($Dest) -or `
        [string]::IsNullOrWhiteSpace($Branch)) {
        $Usage = 'Usage: Invoke-RepoRefresh.ps1 -Servers host1,host2 -User account -Token token ' +
            '-Repo group/project.git -Dest C:\Folder -Branch branch'
        Write-Error -Message $Usage
        exit 1
    }

    if ($null -eq $Token) {
        $Token = ConvertTo-SecureString -String $ProtectedToken
    }

    $ServerList = $Servers.Split(',') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $Engine = [RepoRefreshEngine]::new(
        $ServerList, $User, $Token, $Repo, $Dest, $Branch, $SourceRoot, $Relaunched.IsPresent
    )
    exit $Engine.Run()
} catch {
    Write-Error -Message "Refresh stopped: $($_.Exception.Message)"
    exit 1
} finally {
    Set-Location -Path $Script:StartFolder
}
