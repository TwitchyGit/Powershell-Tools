<#
.SYNOPSIS
Shows username forms for Start-Process -Credential.

.DESCRIPTION
The script evaluates bare, NetBIOS and UPN username forms. Live process launch requires an explicit switch.

.NOTES
Start-Process -Credential is a Windows live check and should use approved test credentials only.
#>
[CmdletBinding()]
param(
    [string]
    $AccountName = 'svc-training',

    [string]
    $DomainNetBIOSName = 'TRAINING',

    [string]
    $DomainDNSRoot = 'training.example.local',

    [pscredential]
    $Credential,

    [switch]
    $LiveWindowsCheck
)

try {
    $CandidateNames = @(
        $AccountName
        ('{0}\{1}' -f $DomainNetBIOSName, $AccountName)
        ('{0}@{1}' -f $AccountName, $DomainDNSRoot)
    ) | Select-Object -Unique

    $IsWindowsHost = $PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows
    foreach ($CandidateName in $CandidateNames) {
        $LiveResult = 'Not run'
        if ($LiveWindowsCheck) {
            if (-not $IsWindowsHost) {
                $LiveResult = 'Skipped because host is not Windows'
            } elseif ($null -eq $Credential) {
                $LiveResult = 'Skipped because no PSCredential was supplied'
            } else {
                $CandidateCredential = [pscredential]::new($CandidateName, $Credential.Password)
                $StartParams = @{
                    FilePath = Join-Path -Path $PSHOME -ChildPath 'pwsh.exe'
                    ArgumentList = @('-NoProfile', '-NonInteractive', '-Command', 'exit 0')
                    Credential = $CandidateCredential
                    WindowStyle = 'Hidden'
                    Wait = $true
                    PassThru = $true
                    ErrorAction = 'Stop'
                }
                $Process = Start-Process @StartParams
                $LiveResult = 'ExitCode {0}' -f $Process.ExitCode
            }
        }

        [pscustomobject]@{
            CandidateName = $CandidateName
            NameForm = if ($CandidateName -like '*@*') {
                'UPN'
            } elseif ($CandidateName -like '*\*') {
                'NetBIOS'
            } else {
                'Bare'
            }
            LiveWindowsCheck = [bool]$LiveWindowsCheck
            LiveResult = $LiveResult
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
