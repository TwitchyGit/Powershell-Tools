<#
.SYNOPSIS
Shows username forms for credential-bound process launch training.

.DESCRIPTION
The script evaluates bare, NetBIOS and UPN username forms without launching a process.
#>
[CmdletBinding()]
param(
    [string]
    $AccountName = 'svc-training',

    [string]
    $DomainNetBIOSName = 'TRAINING',

    [string]
    $DomainDNSRoot = 'training.example.local'
)

try {
    $CandidateNames = @(
        $AccountName
        ('{0}\{1}' -f $DomainNetBIOSName, $AccountName)
        ('{0}@{1}' -f $AccountName, $DomainDNSRoot)
    ) | Select-Object -Unique

    $IsWindowsHost = $PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows
    foreach ($CandidateName in $CandidateNames) {
        [pscustomobject]@{
            CandidateName = $CandidateName
            NameForm = if ($CandidateName -like '*@*') {
                'UPN'
            } elseif ($CandidateName -like '*\*') {
                'NetBIOS'
            } else {
                'Bare'
            }
            ExampleUse = 'Use this name form when building a PSCredential for an approved Windows live check.'
            HostPlatform = if ($IsWindowsHost) { 'Windows' } else { 'NonWindows' }
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
