# Determine if the Debug flag is set.
[CmdletBinding()]
param()

if ($PSBoundParameters['Debug'].IsPresent) {
    Set-PSDebug -Trace 1
}

# Event log function
# 1001 - Information
# 2001 - Warning
# 3001 - Error
function EventWriter($String, $EntryType, $EventID) {
    try {
        LogOutput $String
        $messageText = [string]$String
        $EvtString = $messageText.Substring(
            0,
            [Math]::Min($messageText.Length, 32766)
        )

        # Verify event source exists
        if (-not [System.Diagnostics.EventLog]::SourceExists($ConfDailySource)) {
            LogWarn "Event source '$ConfDailySource' does not exist"
            return
        }

        Write-EventLog -LogName $ConfEventLog -Source $ConfDailySource -EntryType $EntryType -EventId $EventID -Message $EvtString -ErrorAction Stop
    } catch {
        LogError "Failed to write to event log: $($_.Exception.Message)"
        $script:AnyError = $true
        $script:ResultCode = 1
    }
}

# Main processing
$ResultCode = 0
$AnyError = $false
$TranscriptStarted = $false

# Import required variables. DR_Pool must be recorded in BackupPoolName.cfg.
$Script:BASEDIR = $PSScriptRoot
try {
    Import-Module "$BASEDIR\ConfigModule.psm1" -Force -ErrorAction Stop
} catch {
    Write-Error "Configuration errors need to be resolved. $($_.Exception.Message)"
    exit 1
}

# Create the log directory.
if (-not (Test-Path -LiteralPath $ConfLogDir -PathType Container)) {
    try {
        New-Item -ItemType Directory -Path $ConfLogDir -Force -ErrorAction Stop | Out-Null
    } catch {
        Write-Error "Unable to create the log directory '$ConfLogDir': $($_.Exception.Message)"
        exit 1
    }
}

# Pick up the correct logs from ConfigModule.psm1.
$LogTranscript = $ConfDailyLogTranscript
Set-LogFile -Path $ConfDailyLogfile

# Check that BackupPoolName exists and contains Pool.
if ($ConfBackupPoolName -notmatch 'Pool') {
    LogError "BackupPoolName is missing from D:\Vault_Backup-LocalConfig\BackupPoolName.cfg"
    exit 1
}

# Create email variables. Anonymous SMTP is used only where the environment permits it.
$serv = $env:COMPUTERNAME
$anonPass = ConvertTo-SecureString 'anonymous' -AsPlainText -Force
$anonCred = New-Object System.Management.Automation.PSCredential($ConfAnonUser, $anonPass)

# Start the transcript and create the daily summary log.
try {
    Start-Transcript -Path $LogTranscript -Append -NoClobber -ErrorAction Stop
    $TranscriptStarted = $true
} catch {
    LogError "Unable to write to $ConfLogDir"
    LogError $_.Exception.Message
    $AnyError = $true
}

# Read the tsparm.ini configuration file.
$ConfigFile = 'C:\Program Files (x86)\PrivateArk\Replicate\tsparm.ini'
try {
    $tsparm = Get-Content -LiteralPath $ConfigFile -ErrorAction Stop
} catch {
    LogError "Unable to read $ConfigFile"
    LogError $_.Exception.Message
    $AnyError = $true
}

if ($tsparm) {
    $tsparm | Where-Object {
        $_ -notmatch '^#.*' -and
        $_ -notmatch '^\s*$' -and
        $_ -notmatch '^\['
    } | ForEach-Object {
        $Confvar = $_ -split '=', 2
        if ($Confvar.Count -eq 2) {
            $variableName = $Confvar[0].Trim()
            $variableValue = $Confvar[1].Trim()
            New-Variable -Name $variableName -Value $variableValue -Force -Scope Script
            LogOutput "Backup directory set as $variableValue"
        }
    }
}

# Verify that tsparm:SafesDirectory exists.
if (-not (Test-Path -LiteralPath $SafesDirectory -PathType Container)) {
    LogError "Unable to write to $SafesDirectory"
    $AnyError = $true
}

# Verify that the PAReplicate credential file exists and is readable.
if (-not (Test-Path -LiteralPath $ConfCredFile -PathType Leaf)) {
    LogError "Credential file does not exist: $ConfCredFile"
    $AnyError = $true
} else {
    try {
        $credentialStream = [System.IO.File]::Open(
            $ConfCredFile,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        $credentialStream.Dispose()
    } catch {
        LogError "Unable to read $ConfCredFile"
        LogError $_.Exception.Message
        $AnyError = $true
    }
}

if ($AnyError) {
    if ($TranscriptStarted) {
        Stop-Transcript -ErrorAction SilentlyContinue
    }
    exit 1
}

# Create a timer to track how long the backup takes.
$Script:StartTime = $ConfTodaysDate
$Elapsed = [System.Diagnostics.Stopwatch]::StartNew()

LogOutput "Script started at $Script:StartTime"
EventWriter "INFO: Daily (Incremental) backup running for CyberArk Vault" Information 1001

# Run PAReplicate.
$replicateDirectory = 'C:\Program Files (x86)\PrivateArk\Replicate'
$replicateExecutable = Join-Path $replicateDirectory 'PAReplicate.exe'
$processArguments = '/logonfromfile "{0}" /BackupPoolName "{1}"' -f (
    $ConfCredFile,
    $ConfBackupPoolName
)

try {
    $process = Start-Process `
        -FilePath $replicateExecutable `
        -WorkingDirectory $replicateDirectory `
        -ArgumentList $processArguments `
        -NoNewWindow `
        -PassThru `
        -Wait `
        -RedirectStandardOutput $ConfReplicateLog `
        -RedirectStandardError $ConfReplicateErr `
        -ErrorAction Stop

    if ($process.ExitCode -ne 0) {
        LogError "PAReplicate process failed with exit code $($process.ExitCode)"
        $AnyError = $true
    }
} catch {
    LogError "PAReplicate errors occurred: $($_.Exception.Message)"
    $AnyError = $true
}

$CABLog = @()
if (Test-Path -LiteralPath $ConfReplicateLog -PathType Leaf) {
    try {
        $CABLog = Get-Content -LiteralPath $ConfReplicateLog -ErrorAction Stop
    } catch {
        LogError "Unable to read ${ConfReplicateLog}: $($_.Exception.Message)"
        $AnyError = $true
    }
} else {
    LogError "PAReplicate log does not exist: $ConfReplicateLog"
    $AnyError = $true
}
$CABLogExport = $CABLog | Out-String

if ([bool]($CABLog -match 'PAReplicate ended with errors')) {
    $AnyError = $true
}

if ($AnyError) {
    $ResultCode = 1
    EventWriter $CABLogExport Error 3001

    $CABResult = $CABLog | Select-Object -Last 2
    $mAttach = $ConfReplicateLog
    $MailSubj = "CyberArk Backup Finished with Errors on $serv"
    LogOutput "$MailSubj, sending the log to $ConfMailTo"
    $MailBody = "`n`nThe CyberArkBackup task has finished on $serv.`n`nThe results are as follows:`n`n$CABResult`n`nFurther logs can be found under D:\Logs\Vault_Backup\"
    try {
        Send-MailMessage -To $ConfMailTo -Subject $MailSubj -Body $MailBody -From $ConfMailFrom -Credential $anonCred -SmtpServer $ConfSMTPHost -Attachments $mAttach -ErrorAction Stop
        LogOutput "Email sent to $ConfMailTo"
    } catch {
        LogError "Unable to send email: $($_.Exception.Message)"
    }
} else {
    EventWriter $CABLogExport Information 1001

    $CABResult = $CABLog | Select-Object -Last 1
    $MailSubj = "CyberArk Backup Finished Successfully on $serv"
    LogOutput $MailSubj
    $MailBody = "`n`nDaily CyberArk Backup task has finished on $serv.`n`nThe results are as follows:`n`n$CABResult`n`nFurther logs can be found under D:\Logs\Vault_Backup\"
    try {
        Send-MailMessage -To $ConfMailTo -Subject $MailSubj -Body $MailBody -From $ConfMailFrom -Credential $anonCred -SmtpServer $ConfSMTPHost -ErrorAction Stop
        LogOutput "Email sent to $ConfMailTo"
    } catch {
        LogError "Unable to send email: $($_.Exception.Message)"
        $ResultCode = 1
    }
}

$Elapsed.Stop()
LogOutput "Script completed at $(Get-Date). Total Elapsed Time: $($Elapsed.Elapsed.ToString())"
EventWriter "INFO: Incremental backup completed at $(Get-Date) - Total Elapsed Time: $($Elapsed.Elapsed.ToString())" Information 1001

if ($TranscriptStarted) {
    try {
        Stop-Transcript -ErrorAction Stop
        $TranscriptStarted = $false
    } catch {
        LogError "Unable to stop the transcript: $($_.Exception.Message)"
        $ResultCode = 1
    }
}

# Copy the transcript into the replication area so the index file is backed up.
$indexFile = Join-Path $SafesDirectory 'Vault_Daily_Backup_Index_File.txt'
try {
    Copy-Item -LiteralPath $LogTranscript -Destination $indexFile -Force -ErrorAction Stop
    LogOutput "Index file copied to $indexFile"
    EventWriter "INFO: Index file copied to $indexFile" Information 1001
} catch {
    LogError "Unable to copy the index file to ${indexFile}: $($_.Exception.Message)"
    $ResultCode = 1
}

if ($PSBoundParameters['Debug'].IsPresent) {
    Set-PSDebug -Trace 0
}

# Send exit 0 or 1 to AutoSys.
LogOutput "Sending exit $ResultCode for AutoSys."
exit [int]$ResultCode
