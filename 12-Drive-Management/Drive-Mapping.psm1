<#
Example usage:

    Import-Module .\Drive-Mapping.psm1

    if (-not (Mount-ShareDrive -Name 'Tmp' -Root "\\$Computer\c$")) {
        $Fail = 1
    }

    # With explicit credentials
    Mount-ShareDrive -Name 'Tmp' -Root "\\$Computer\c$" -Credential $Cred

    Get-ChildItem -LiteralPath 'Tmp:\'

    Dismount-ShareDrive -Name 'Tmp' | Out-Null
#>

$script:MountCount = @{}

function Mount-ShareDrive {
    <#
    .SYNOPSIS
    Maps a share to a global PSDrive. Safe to call repeatedly for the same name and root.
    .PARAMETER Name
    PSDrive name without the colon.
    .PARAMETER Root
    UNC path to map, such as \\server\c$.
    .PARAMETER Credential
    Optional account. The current account is used when omitted.
    .OUTPUTS
    Boolean. True when the drive is mapped and reachable.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Root,
        [System.Management.Automation.PSCredential]$Credential
    )

    $Key = $Name.ToUpper()
    $Existing = Get-PSDrive -Name $Name -ErrorAction SilentlyContinue
    if ($Existing) {
        if ($Existing.Root.TrimEnd('\') -ieq $Root.TrimEnd('\')) {
            $script:MountCount[$Key] = [int]$script:MountCount[$Key] + 1
            return $true
        }
        Remove-PSDrive -Name $Name -Scope Global -Force -ErrorAction SilentlyContinue
        $script:MountCount.Remove($Key)
    }

    $Params = @{
        Name        = $Name
        PSProvider  = 'FileSystem'
        Root        = $Root
        Scope       = 'Global'
        ErrorAction = 'Stop'
    }
    if ($Credential) {
        $Params.Credential = $Credential
    }

    for ($Attempt = 1; $Attempt -le 2; $Attempt++) {
        try {
            New-PSDrive @Params | Out-Null

            # New-PSDrive can succeed without proving the account can open the share.
            if (-not (Test-Path -LiteralPath "${Name}:\" -PathType Container)) {
                Remove-PSDrive -Name $Name -Scope Global -Force -ErrorAction SilentlyContinue
                Write-Error -Message 'Drive mapped but the root is not accessible' -ErrorAction Stop
            }

            $script:MountCount[$Key] = 1
            return $true
        } catch {
            # Error 1219: a stale connection to the same server under another account blocks the mount.
            if ($Attempt -eq 1 -and $_.Exception.Message -match '1219|multiple connections') {
                net use $Root /delete /y 2>&1 | Out-Null
                continue
            }
            Write-Error -Message "Mount of $Root as ${Name}: failed: $($_.Exception.Message)"
            return $false
        }
    }
}

function Dismount-ShareDrive {
    <#
    .SYNOPSIS
    Releases one mount request. The drive is removed when the last request releases it.
    .PARAMETER Name
    PSDrive name without the colon.
    .OUTPUTS
    Boolean. True when the drive is gone or still held by another request.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    $Key = $Name.ToUpper()

    if (-not (Get-PSDrive -Name $Name -ErrorAction SilentlyContinue)) {
        $script:MountCount.Remove($Key)
        return $true
    }

    if ($script:MountCount[$Key] -gt 1) {
        $script:MountCount[$Key]--
        return $true
    }

    try {
        Remove-PSDrive -Name $Name -Scope Global -Force -ErrorAction Stop
        $script:MountCount.Remove($Key)
        return $true
    } catch {
        Write-Error -Message "Dismount of ${Name}: failed: $($_.Exception.Message)"
        return $false
    }
}

Export-ModuleMember -Function Mount-ShareDrive, Dismount-ShareDrive