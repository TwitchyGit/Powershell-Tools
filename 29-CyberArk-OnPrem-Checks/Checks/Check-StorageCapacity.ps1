<#
.SYNOPSIS
    Tests free disk space on each component server.

.DESCRIPTION
    A disk fails if free space is below FailFreePercent or FailFreeGB.
    A disk warns if free space is below WarnFreePercent or WarnFreeGB.
    Limits come from the Storage section of the settings. A role can have its own limits.
    This check only reads data. Simulation only stops the report files.

.PARAMETER Role
    Roles to test. Default is all Windows roles.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER Simulate
    Makes no changes. No report files are written.

.EXAMPLE
    .\Check-StorageCapacity.ps1 -Verbose
#>
[CmdletBinding()]
param(
    [string[]]$Role,
    [string[]]$ComputerName,
    [switch]$Simulate,
    [pscredential]$RemoteCredential,
    [string]$OutputDirectory
)

if ($PSBoundParameters.ContainsKey('Debug')) { $DebugPreference = 'SilentlyContinue' }

$settingsModule = $env:ONPREM_CHECKS_SETTINGS
if ([string]::IsNullOrWhiteSpace($settingsModule)) {
    $settingsModule = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'Config\CheckSettings.psm1'
}
Import-Module -Name $settingsModule -Force -ErrorAction Stop

$ctx = Start-Check -Name 'StorageCapacity' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$probe = {
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Drive     = [string]$_.DeviceID
            Label     = [string]$_.VolumeName
            SizeBytes = [int64]$_.Size
            FreeBytes = [int64]$_.FreeSpace
        }
    }
}

try {
    $cfg = (Get-CheckSettings).Storage
    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Testing disks on {0} server(s)." -f $targets.Count)

    foreach ($t in $targets) {
        $limit = @{
            WarnFreePercent = $cfg.WarnFreePercent
            FailFreePercent = $cfg.FailFreePercent
            WarnFreeGB      = $cfg.WarnFreeGB
            FailFreeGB      = $cfg.FailFreeGB
        }
        if ($cfg.RoleOverrides.ContainsKey($t.Role)) {
            foreach ($key in @($cfg.RoleOverrides[$t.Role].Keys)) { $limit[$key] = $cfg.RoleOverrides[$t.Role][$key] }
        }
        Write-CheckLog -Level Debug -Message ("Limits for {0}: warn {1}% or {2} GB, fail {3}% or {4} GB." -f
            $t.Host, $limit.WarnFreePercent, $limit.WarnFreeGB, $limit.FailFreePercent, $limit.FailFreeGB)

        try {
            $disks = @(Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $probe -Credential $RemoteCredential)
        } catch {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'Disk query' -Status Error -Message $_.Exception.Message
            continue
        }

        foreach ($disk in $disks) {
            if (@($cfg.Drives).Count -gt 0 -and ($disk.Drive -notin @($cfg.Drives))) { continue }
            if ($disk.SizeBytes -le 0) { continue }

            $freePercent = [math]::Round(($disk.FreeBytes / $disk.SizeBytes) * 100, 1)
            $freeGB = [math]::Round($disk.FreeBytes / 1GB, 1)
            $sizeGB = [math]::Round($disk.SizeBytes / 1GB, 1)
            $text = '{0} GB free of {1} GB ({2}%).' -f $freeGB, $sizeGB, $freePercent

            if ($freePercent -lt $limit.FailFreePercent -or $freeGB -lt $limit.FailFreeGB) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $disk.Drive -Status Fail -Message $text
            } elseif ($freePercent -lt $limit.WarnFreePercent -or $freeGB -lt $limit.WarnFreeGB) {
                Add-Finding -Role $t.Role -Target $t.Host -Item $disk.Drive -Status Warn -Message $text
            } else {
                Add-Finding -Role $t.Role -Target $t.Host -Item $disk.Drive -Status Pass -Message $text
            }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
