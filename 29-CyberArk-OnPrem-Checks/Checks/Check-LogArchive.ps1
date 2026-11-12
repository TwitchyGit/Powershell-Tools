<#
.SYNOPSIS
    Copies recent component log files to a local archive folder. It uses WinRM and no SMB.

.DESCRIPTION
    For each server the check reads the LogPaths of its role and copies files that
    changed in the last AgeHours hours. Only names in LogArchive.Include are copied.
    Files go to:
      <DestinationRoot>\<Environment>\<Role>\<Server>\<yyyyMMdd>\...

    File names and file content travel over a PowerShell remoting (WinRM) session.
    The check opens no administrative share and no UNC path. DestinationRoot must be a
    local folder. A UNC path or a mapped network drive is refused while
    Security.BlockSmbPaths is on.

    A file that already exists at the destination with the same size and time is not copied again.
    The check opens source files with shared read access, so it can copy logs that a
    service still has open.

    Simulation: the check lists the files it would copy. It copies nothing and creates no folders.

.PARAMETER Role
    Roles to collect from. Default is all Windows roles that have LogPaths.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER AgeHours
    Overrides LogArchive.AgeHours.

.PARAMETER Simulate
    Makes no changes. Nothing is copied. No report files are written.

.EXAMPLE
    .\Check-LogArchive.ps1 -Role CPM -Simulate -Verbose
#>
[CmdletBinding()]
param(
    [string[]]$Role,
    [string[]]$ComputerName,
    [int]$AgeHours,
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

$ctx = Start-Check -Name 'LogArchive' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

# Runs on the server. Lists the files that are in scope.
$lister = {
    param([string]$Path, [bool]$Recurse, [datetime]$Cutoff, [string[]]$Include)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        return [pscustomobject]@{ Found = $false; Files = @() }
    }
    $root = (Get-Item -LiteralPath $Path).FullName.TrimEnd('\')
    $files = foreach ($file in (Get-ChildItem -LiteralPath $Path -File -Recurse:$Recurse -Force -ErrorAction SilentlyContinue)) {
        if ($file.LastWriteTime -lt $Cutoff) { continue }
        $wanted = $false
        foreach ($pattern in $Include) {
            if ($file.Name -like $pattern) { $wanted = $true; break }
        }
        if (-not $wanted) { continue }
        [pscustomobject]@{
            FullName   = $file.FullName
            Relative   = $file.FullName.Substring($root.Length).TrimStart('\')
            Length     = [int64]$file.Length
            WriteTicks = [int64]$file.LastWriteTimeUtc.Ticks
        }
    }
    return [pscustomobject]@{ Found = $true; Files = @($files) }
}

try {
    $settings = Get-CheckSettings
    $cfg = $settings.LogArchive
    $hours = $cfg.AgeHours
    if ($PSBoundParameters.ContainsKey('AgeHours') -and $AgeHours -gt 0) { $hours = $AgeHours }
    $cutoff = (Get-Date).AddHours(-1 * $hours)
    $maxBytes = [int64]$cfg.MaxFileMB * 1MB
    $chunkBytes = [int]([int64]$cfg.ChunkMB * 1MB)
    $dateFolder = Get-Date -Format 'yyyyMMdd'

    Assert-NotSmbPath -Path $cfg.DestinationRoot -Name 'Archive root'
    Write-CheckLog -Level Verbose -Message ("Files changed since {0:yyyy-MM-dd HH:mm} are in scope." -f $cutoff)

    $targets = @(Get-CheckTargets -Role $Role -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Archiving logs from {0} server(s) over WinRM." -f $targets.Count)

    foreach ($t in $targets) {
        $logPaths = @((Get-RoleSettings -Role $t.Role).LogPaths)
        if ($logPaths.Count -eq 0) {
            Write-CheckLog -Level Verbose -Message ("Role {0} has no LogPaths. Skipped {1}." -f $t.Role, $t.Host)
            continue
        }

        $session = $null
        try {
            $session = New-TargetSession -ComputerName $t.Host -Credential $RemoteCredential
        } catch {
            Add-Finding -Role $t.Role -Target $t.Host -Item 'WinRM session' -Status Error -Message $_.Exception.Message
            continue
        }

        try {
            foreach ($logPath in $logPaths) {
                $item = [string]$logPath.Path
                try {
                    $arguments = @($item, [bool]$logPath.Recurse, $cutoff, [string[]]@($cfg.Include))
                    $listing = Invoke-OnSession -Session $session -ScriptBlock $lister -ArgumentList $arguments
                    if (-not $listing.Found) {
                        Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Warn -Message 'Source folder not found.'
                        continue
                    }

                    $files = @($listing.Files)
                    Write-CheckLog -Level Debug -Message ("{0}: {1} file(s) in scope under {2}." -f $t.Host, $files.Count, $item)

                    $destBase = Join-Path -Path $cfg.DestinationRoot -ChildPath ('{0}\{1}\{2}\{3}' -f $settings.Environment, $t.Role, $t.Host, $dateFolder)
                    $copied = 0
                    $unchanged = 0
                    $tooLarge = 0
                    $failed = 0

                    foreach ($file in $files) {
                        if ($file.Length -gt $maxBytes) { $tooLarge++; continue }

                        $destFile = Join-Path -Path $destBase -ChildPath $file.Relative
                        $sourceTime = New-Object System.DateTime([int64]$file.WriteTicks, [System.DateTimeKind]::Utc)

                        if (Test-Path -LiteralPath $destFile -PathType Leaf) {
                            $existing = Get-Item -LiteralPath $destFile
                            $sameTime = [math]::Abs(($existing.LastWriteTimeUtc - $sourceTime).TotalSeconds) -le 2
                            if ($existing.Length -eq $file.Length -and $sameTime) { $unchanged++; continue }
                        }

                        if ($Simulate) {
                            Write-CheckLog -Level Sim -Message ("Would copy '{0}' on {1} to '{2}'." -f $file.FullName, $t.Host, $destFile)
                            $copied++
                            continue
                        }

                        try {
                            $destDir = Split-Path -Parent $destFile
                            if (-not (Test-Path -LiteralPath $destDir)) {
                                New-Item -ItemType Directory -Path $destDir -Force -ErrorAction Stop | Out-Null
                            }
                            if ($null -eq $session) {
                                Copy-FileShared -Source $file.FullName -Destination $destFile
                            } else {
                                $bytes = Receive-RemoteFile -Session $session -RemotePath $file.FullName -Destination $destFile -ChunkBytes $chunkBytes
                                if ($bytes -lt $file.Length) {
                                    throw ('Received {0} byte(s). Expected at least {1}.' -f $bytes, $file.Length)
                                }
                            }
                            (Get-Item -LiteralPath $destFile).LastWriteTimeUtc = $sourceTime
                            $copied++
                        } catch {
                            $failed++
                            Write-CheckLog -Level Warn -Message ("Copy failed for '{0}' on {1}: {2}" -f $file.FullName, $t.Host, $_.Exception.Message)
                        }
                    }

                    $verb = 'Copied'
                    if ($Simulate) { $verb = 'Would copy' }
                    $text = '{0} {1}. Unchanged {2}. Too large {3}. Failed {4}.' -f $verb, $copied, $unchanged, $tooLarge, $failed
                    if ($failed -gt 0) {
                        Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Fail -Message $text
                    } elseif ($tooLarge -gt 0) {
                        Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Warn -Message $text
                    } else {
                        Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Pass -Message $text
                    }
                } catch {
                    Add-Finding -Role $t.Role -Target $t.Host -Item $item -Status Error -Message $_.Exception.Message
                }
            }
        } finally {
            if ($null -ne $session) { Remove-PSSession -Session $session -ErrorAction SilentlyContinue }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
