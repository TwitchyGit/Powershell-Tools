function Mount-ShareDrive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Root,

        [System.Management.Automation.PSCredential]$Credential
    )

    if (Get-PSDrive -Name $Name -ErrorAction SilentlyContinue) {
        Remove-PSDrive -Name $Name -Force -ErrorAction SilentlyContinue
    }

    $Params = @{
        Name        = $Name
        PSProvider  = 'FileSystem'
        Root        = $Root
        Scope       = 'Script'
        ErrorAction = 'Stop'
    }
    if ($Credential) {
        $Params.Credential = $Credential
    }

    try {
        New-PSDrive @Params | Out-Null
        return $true
    } catch {
        Write-Error -Message "Mount of $Root as ${Name}: failed: $($_.Exception.Message)"
        return $false
    }
}

function Dismount-ShareDrive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if (-not (Get-PSDrive -Name $Name -ErrorAction SilentlyContinue)) {
        return $true
    }

    try {
        Remove-PSDrive -Name $Name -Scope Script -Force -ErrorAction Stop
        return $true
    } catch {
        Write-Error -Message "Dismount of ${Name}: failed: $($_.Exception.Message)"
        return $false
    }
}
