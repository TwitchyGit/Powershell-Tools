<#
.SYNOPSIS
    Compares the files of one component role across its servers.

.DESCRIPTION
    For each role the check hashes every file in the role ParityPaths on every server
    and compares the results. It reports:
      - files that are missing on some servers
      - files with different content (different SHA256 hash)
    Files that match Parity.ExpectedToDiffer are reported as Info, not Fail.
    Files that match Parity.Exclude are ignored.

    A role needs at least two servers (active plus standby, or more) for a comparison.
    Unless -Simulate is set, the check also writes an inventory CSV for each role.

.PARAMETER Role
    Roles to compare. Default is Parity.Roles from the settings.

.PARAMETER ComputerName
    Replaces the server list. Use it with exactly one -Role.

.PARAMETER Simulate
    Makes no changes. No inventory, report or log files are written.

.EXAMPLE
    .\Check-FileParity.ps1 -Role CPM -Verbose
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

$ctx = Start-Check -Name 'FileParity' -Simulate:$Simulate -Bound $PSBoundParameters -OutputDirectory $OutputDirectory

$probe = {
    param([string[]]$Directories, [string[]]$Exclude, [int]$MaxFiles, [int64]$MaxHashBytes)

    foreach ($dir in $Directories) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
            [pscustomobject]@{ Directory = $dir; RelativePath = ''; Hash = ''; Version = ''; Size = 0; Error = 'Folder not found.' }
            continue
        }
        $root = (Get-Item -LiteralPath $dir).FullName.TrimEnd('\')
        $count = 0
        foreach ($file in (Get-ChildItem -LiteralPath $dir -Recurse -File -Force -ErrorAction SilentlyContinue)) {
            $skip = $false
            foreach ($pattern in $Exclude) {
                if ($file.FullName -like $pattern) { $skip = $true; break }
            }
            if ($skip) { continue }

            $count++
            if ($count -gt $MaxFiles) {
                [pscustomobject]@{ Directory = $dir; RelativePath = ''; Hash = ''; Version = ''; Size = 0; Error = ('File limit {0} reached. Folder is only partly compared.' -f $MaxFiles) }
                break
            }

            $row = [pscustomobject]@{
                Directory    = $dir
                RelativePath = $file.FullName.Substring($root.Length + 1)
                Hash         = ''
                Version      = ''
                Size         = [int64]$file.Length
                Error        = ''
            }
            try {
                if ($file.Length -le $MaxHashBytes) {
                    $row.Hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash
                } else {
                    $row.Error = 'File too large to hash.'
                }
                $row.Version = [string]$file.VersionInfo.FileVersion
            } catch {
                $row.Error = $_.Exception.Message
            }
            $row
        }
    }
}

try {
    $settings = Get-CheckSettings
    $cfg = $settings.Parity
    $roles = @($Role | Where-Object { $_ })
    if ($roles.Count -eq 0) { $roles = @($cfg.Roles) }

    $targets = @(Get-CheckTargets -Role $roles -ComputerName $ComputerName -Platform Windows -IncludeStandby)
    Write-CheckLog -Level Info -Message ("Comparing files for {0} role(s)." -f @($targets | Select-Object -ExpandProperty Role -Unique).Count)

    foreach ($roleName in @($targets | Select-Object -ExpandProperty Role -Unique)) {
        $directories = [string[]]@((Get-RoleSettings -Role $roleName).ParityPaths)
        if ($directories.Count -eq 0) {
            Write-CheckLog -Level Verbose -Message ("Role {0} has no ParityPaths. Skipped." -f $roleName)
            continue
        }

        $servers = @($targets | Where-Object { $_.Role -eq $roleName })
        $inventory = @{}
        foreach ($t in $servers) {
            try {
                $arguments = @(, $directories) + @(, [string[]]@($cfg.Exclude)) + @([int]$cfg.MaxFiles, ([int64]$cfg.MaxHashMB * 1MB))
                $rows = @(Invoke-OnTarget -ComputerName $t.Host -ScriptBlock $probe -ArgumentList $arguments -Credential $RemoteCredential)
                $inventory[$t.Host] = $rows
                Write-CheckLog -Level Verbose -Message ("{0}: {1} file row(s)." -f $t.Host, $rows.Count)
            } catch {
                Add-Finding -Role $roleName -Target $t.Host -Item 'File scan' -Status Error -Message $_.Exception.Message
            }
        }

        $scanned = @($inventory.Keys | Sort-Object)
        if ($scanned.Count -lt 2) {
            Add-Finding -Role $roleName -Target ($scanned -join ', ') -Item 'Comparison' -Status Skipped -Message 'Fewer than two servers returned data.'
            continue
        }

        # Report scan problems first. Then compare only normal file rows.
        $index = @{}
        foreach ($srv in $scanned) {
            foreach ($row in $inventory[$srv]) {
                if ($row.Error -and -not $row.RelativePath) {
                    Add-Finding -Role $roleName -Target $srv -Item $row.Directory -Status Warn -Message $row.Error
                    continue
                }
                if ($row.Error) {
                    Add-Finding -Role $roleName -Target $srv -Item $row.RelativePath -Status Warn -Message $row.Error
                    continue
                }
                $key = ('{0}|{1}' -f $row.Directory, $row.RelativePath).ToLowerInvariant()
                if (-not $index.ContainsKey($key)) {
                    $index[$key] = @{ Path = $row.RelativePath; Servers = @{} }
                }
                $index[$key].Servers[$srv] = $row
            }
        }

        $differences = 0
        foreach ($key in ($index.Keys | Sort-Object)) {
            $entry = $index[$key]
            $present = @($entry.Servers.Keys | Sort-Object)
            $missing = @($scanned | Where-Object { $_ -notin $present })
            $leaf = Split-Path -Leaf $entry.Path
            $mayDiffer = Test-AnyLike -Value $leaf -Pattern @($cfg.ExpectedToDiffer)

            if ($missing.Count -gt 0) {
                $differences++
                Add-Finding -Role $roleName -Target ($missing -join ', ') -Item $entry.Path -Status Fail -Message 'File is missing on these servers.'
                continue
            }

            $groups = @($present | Group-Object -Property { $entry.Servers[$_].Hash })
            if ($groups.Count -gt 1) {
                $detail = ($groups | ForEach-Object {
                    '{0}: {1}' -f ([string]$_.Name).Substring(0, [math]::Min(8, ([string]$_.Name).Length)), ($_.Group -join ',')
                }) -join ' | '
                if ($mayDiffer) {
                    Add-Finding -Role $roleName -Target 'All servers' -Item $entry.Path -Status Info -Message ('Content differs. This file may differ. ' + $detail)
                } else {
                    $differences++
                    Add-Finding -Role $roleName -Target 'All servers' -Item $entry.Path -Status Fail -Message ('Content differs. ' + $detail)
                }
            }
        }

        if ($differences -eq 0) {
            Add-Finding -Role $roleName -Target ($scanned -join ', ') -Item 'File parity' -Status Pass `
                -Message ('{0} file(s) compared. No unexpected differences.' -f $index.Count)
        }

        $inventoryFile = Join-Path -Path $ctx.OutputDirectory -ChildPath ('FileParity_{0}_inventory.csv' -f $roleName)
        if ($Simulate) {
            Write-CheckLog -Level Sim -Message ("Would write the file inventory to '{0}'." -f $inventoryFile)
        } else {
            try {
                if (-not (Test-Path -LiteralPath $ctx.OutputDirectory)) {
                    New-Item -ItemType Directory -Path $ctx.OutputDirectory -Force -ErrorAction Stop | Out-Null
                }
                $flat = foreach ($srv in $scanned) {
                    foreach ($row in $inventory[$srv]) {
                        [pscustomobject]@{
                            Server = $srv; Directory = $row.Directory; RelativePath = $row.RelativePath
                            Version = $row.Version; Size = $row.Size; Hash = $row.Hash; Error = $row.Error
                        }
                    }
                }
                $flat | Export-Csv -LiteralPath $inventoryFile -NoTypeInformation -Encoding UTF8 -ErrorAction Stop
                Write-CheckLog -Level Info -Message ("Inventory: {0}" -f $inventoryFile)
            } catch {
                Write-CheckLog -Level Warn -Message ("Could not write the inventory: {0}" -f $_.Exception.Message)
            }
        }
    }
} catch {
    Add-Finding -Target $env:COMPUTERNAME -Item 'Check execution' -Status Error -Message $_.Exception.Message
}

exit (Complete-Check)
