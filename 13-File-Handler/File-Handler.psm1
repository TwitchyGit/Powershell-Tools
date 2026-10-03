<#
Example usage:

    Import-Module .\File-Handler.psm1

    # List the processes holding files open under the directory
    Get-DirectoryLockProcess -Path 'D:\Target'

    # Preview, then terminate
    Stop-DirectoryLockProcess -Path 'D:\Target' -WhatIf
    Stop-DirectoryLockProcess -Path 'D:\Target' -InformationAction Continue

Requires Windows and an elevated session. Uses the Windows Restart Manager API, so no handle.exe or openfiles.
#>

$script:ProtectedProcessNames = @(
    'Idle',
    'System',
    'Registry',
    'smss',
    'csrss',
    'wininit',
    'winlogon',
    'lsass',
    'services'
)

$script:AppTypeNames = @{
    0    = 'Unknown'
    1    = 'MainWindow'
    2    = 'OtherWindow'
    3    = 'Service'
    4    = 'Explorer'
    5    = 'Console'
    1000 = 'Critical'
}

$script:RestartManagerSource = @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public class FileLockInfo {
    public int ProcessId;
    public long StartFileTime;
    public string AppName;
    public string ServiceName;
    public int AppType;
}

public static class RestartManagerApi {
    private const int ERROR_MORE_DATA = 234;

    [StructLayout(LayoutKind.Sequential)]
    private struct RM_UNIQUE_PROCESS {
        public int dwProcessId;
        public System.Runtime.InteropServices.ComTypes.FILETIME ProcessStartTime;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct RM_PROCESS_INFO {
        public RM_UNIQUE_PROCESS Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)] public string strAppName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string strServiceShortName;
        public int ApplicationType;
        public uint AppStatus;
        public uint TSSessionId;
        [MarshalAs(UnmanagedType.Bool)] public bool bRestartable;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    private static extern int RmStartSession(out uint handle, int flags, StringBuilder key);

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    private static extern int RmRegisterResources(uint handle, uint fileCount, string[] files,
        uint appCount, RM_UNIQUE_PROCESS[] apps, uint serviceCount, string[] services);

    [DllImport("rstrtmgr.dll")]
    private static extern int RmGetList(uint handle, out uint needed, ref uint count,
        [In, Out] RM_PROCESS_INFO[] info, ref uint reasons);

    [DllImport("rstrtmgr.dll")]
    private static extern int RmEndSession(uint handle);

    public static List<FileLockInfo> GetLockers(string[] files) {
        uint session;
        var key = new StringBuilder(33);
        int rc = RmStartSession(out session, 0, key);
        if (rc != 0) throw new Win32Exception(rc);
        try {
            rc = RmRegisterResources(session, (uint)files.Length, files, 0, null, 0, null);
            if (rc != 0) throw new Win32Exception(rc);

            var result = new List<FileLockInfo>();
            uint needed = 0, count = 0, reasons = 0;
            rc = RmGetList(session, out needed, ref count, null, ref reasons);
            for (int attempt = 0; rc == ERROR_MORE_DATA && attempt < 5; attempt++) {
                var info = new RM_PROCESS_INFO[needed];
                count = needed;
                rc = RmGetList(session, out needed, ref count, info, ref reasons);
                if (rc != 0) continue;
                for (int i = 0; i < count; i++) {
                    var ft = info[i].Process.ProcessStartTime;
                    result.Add(new FileLockInfo {
                        ProcessId = info[i].Process.dwProcessId,
                        StartFileTime = ((long)ft.dwHighDateTime << 32) | (long)(uint)ft.dwLowDateTime,
                        AppName = info[i].strAppName,
                        ServiceName = info[i].strServiceShortName,
                        AppType = info[i].ApplicationType
                    });
                }
            }
            if (rc != 0) throw new Win32Exception(rc);
            return result;
        } finally {
            RmEndSession(session);
        }
    }
}
'@

function Initialize-RestartManager {
    [CmdletBinding()]
    param()

    if (-not ('RestartManagerApi' -as [type])) {
        Add-Type -TypeDefinition $script:RestartManagerSource -ErrorAction Stop
    }
}

function Test-Elevated {
    [CmdletBinding()]
    param()

    $Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [System.Security.Principal.WindowsPrincipal]::new($Identity)
    return $Principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DirectoryLockProcess {
    <#
    .SYNOPSIS
    Lists the processes that hold files open under a directory.
    .DESCRIPTION
    Enumerates every file under the directory and asks the Windows Restart Manager which processes and services
    use them. A process that only has the directory as its working directory is not reported.
    .PARAMETER Path
    Directory to check. A drive root or share root is refused.
    .PARAMETER BatchSize
    Number of files sent to Restart Manager per query.
    .OUTPUTS
    One object per process or service: ProcessId, ProcessName, ExecutablePath, ApplicationType, ServiceName,
    StartFileTime.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 5000)][int]$BatchSize = 500
    )

    if (-not $IsWindows) {
        Write-Error -Message 'Get-DirectoryLockProcess runs on Windows only' -ErrorAction Stop
    }

    $Resolved = Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue
    if (-not $Resolved -or -not (Test-Path -LiteralPath $Resolved.ProviderPath -PathType Container)) {
        Write-Error -Message "Directory not found: $Path" -ErrorAction Stop
    }

    $FullPath = [System.IO.Path]::GetFullPath($Resolved.ProviderPath)
    if ($FullPath -ieq [System.IO.Path]::GetPathRoot($FullPath)) {
        Write-Error -Message "Refusing to scan a root path: $FullPath" -ErrorAction Stop
    }

    if (-not (Test-Elevated)) {
        Write-Warning -Message 'Session is not elevated. Processes owned by other accounts may not be reported.'
    }

    Initialize-RestartManager

    $Files = @(
        Get-ChildItem -LiteralPath $FullPath -File -Recurse -Force -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty FullName
    )

    $Seen = @{}
    $Lockers = [System.Collections.Generic.List[object]]::new()
    for ($Offset = 0; $Offset -lt $Files.Count; $Offset += $BatchSize) {
        $Last = [Math]::Min($Offset + $BatchSize, $Files.Count) - 1
        $Batch = [string[]]$Files[$Offset..$Last]

        try {
            $Found = [RestartManagerApi]::GetLockers($Batch)
        } catch {
            Write-Error -Message "Restart Manager query failed: $($_.Exception.Message)" -ErrorAction Stop
        }

        foreach ($Info in $Found) {
            $Key = "$($Info.ProcessId)-$($Info.StartFileTime)-$($Info.ServiceName)"
            if ($Seen.ContainsKey($Key)) {
                continue
            }
            $Seen[$Key] = $true

            $Proc = Get-Process -Id $Info.ProcessId -ErrorAction SilentlyContinue
            $ExecutablePath = $null
            if ($Proc) {
                try {
                    $ExecutablePath = $Proc.Path
                } catch {
                    $ExecutablePath = $null
                }
            }

            $TypeName = $script:AppTypeNames[[int]$Info.AppType]
            if (-not $TypeName) {
                $TypeName = 'Unknown'
            }

            $Lockers.Add([PSCustomObject]@{
                ProcessId       = $Info.ProcessId
                ProcessName     = if ($Proc) { $Proc.ProcessName } else { $Info.AppName }
                ExecutablePath  = $ExecutablePath
                ApplicationType = $TypeName
                ServiceName     = $Info.ServiceName
                StartFileTime   = $Info.StartFileTime
            })
        }
    }

    return $Lockers | Sort-Object -Property ProcessId
}

function Stop-DirectoryLockProcess {
    <#
    .SYNOPSIS
    Lists and terminates the processes that hold files open under a directory.
    .DESCRIPTION
    Calls Get-DirectoryLockProcess, then stops each holder. A holder that is a Windows service is stopped with
    Stop-Service so the service host and its other services are left alone. The current process, PID 0 and 4,
    core system processes and Restart Manager critical processes are skipped. A process is only stopped when its
    start time still matches the Restart Manager result, so a reused PID is never hit. Supports -WhatIf.
    .PARAMETER Path
    Directory to check. A drive root or share root is refused.
    .PARAMETER TimeoutSeconds
    Seconds to wait for a stopped process to exit before it is reported as failed.
    .OUTPUTS
    One object per holder: ProcessId, ProcessName, ApplicationType, ServiceName, ExecutablePath, Action, Result,
    Detail. Result is Stopped, Failed or Skipped.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 15
    )

    $Lockers = @(Get-DirectoryLockProcess -Path $Path)
    if ($Lockers.Count -eq 0) {
        Write-Information -MessageData "No processes hold files open under $Path" -InformationAction Continue
        return
    }

    foreach ($Locker in $Lockers) {
        Write-Information -MessageData ("Holder: PID {0} {1} ({2}) {3}" -f
            $Locker.ProcessId, $Locker.ProcessName, $Locker.ApplicationType, $Locker.ServiceName)

        $Action = 'None'
        $Outcome = 'Skipped'
        $Detail = ''

        $IsProtected = $Locker.ProcessId -in 0, 4 -or
            $Locker.ProcessName -in $script:ProtectedProcessNames -or
            $Locker.ApplicationType -eq 'Critical'

        if ($Locker.ProcessId -eq $PID) {
            $Detail = 'Current process'
        } elseif ($IsProtected) {
            $Detail = 'Protected process'
        } elseif ($Locker.ServiceName) {
            $Action = 'Stop-Service'
            if ($PSCmdlet.ShouldProcess("service $($Locker.ServiceName)", 'Stop')) {
                try {
                    Stop-Service -Name $Locker.ServiceName -Force -ErrorAction Stop
                    $Outcome = 'Stopped'
                } catch {
                    $Outcome = 'Failed'
                    $Detail = $_.Exception.Message
                }
            } else {
                $Detail = 'Not confirmed (WhatIf or Confirm declined)'
            }
        } else {
            $Action = 'Stop-Process'
            $Proc = Get-Process -Id $Locker.ProcessId -ErrorAction SilentlyContinue
            $StartFileTime = $null
            if ($Proc) {
                try {
                    $StartFileTime = $Proc.StartTime.ToFileTime()
                } catch {
                    $StartFileTime = $null
                }
            }

            if (-not $Proc) {
                $Detail = 'Already exited'
            } elseif ($StartFileTime -ne $Locker.StartFileTime) {
                $Detail = 'Start time mismatch or unreadable, PID may have been reused'
            } elseif ($PSCmdlet.ShouldProcess("process $($Locker.ProcessName) (PID $($Locker.ProcessId))", 'Stop')) {
                try {
                    Stop-Process -Id $Locker.ProcessId -Force -ErrorAction Stop
                    Wait-Process -Id $Locker.ProcessId -Timeout $TimeoutSeconds -ErrorAction SilentlyContinue
                    if (Get-Process -Id $Locker.ProcessId -ErrorAction SilentlyContinue) {
                        $Outcome = 'Failed'
                        $Detail = "Still running after $TimeoutSeconds seconds"
                    } else {
                        $Outcome = 'Stopped'
                    }
                } catch {
                    $Outcome = 'Failed'
                    $Detail = $_.Exception.Message
                }
            } else {
                $Detail = 'Not confirmed (WhatIf or Confirm declined)'
            }
        }

        [PSCustomObject]@{
            ProcessId       = $Locker.ProcessId
            ProcessName     = $Locker.ProcessName
            ApplicationType = $Locker.ApplicationType
            ServiceName     = $Locker.ServiceName
            ExecutablePath  = $Locker.ExecutablePath
            Action          = $Action
            Result          = $Outcome
            Detail          = $Detail
        }
    }
}

Export-ModuleMember -Function Get-DirectoryLockProcess, Stop-DirectoryLockProcess
