<#
.SYNOPSIS
Shows credential CLIXML scope and portability boundaries.

.DESCRIPTION
The script exports and imports a synthetic credential under a generated sample folder.

.NOTES
On Windows, credential CLIXML is protected by DPAPI for the same user and computer context.
#>
[CmdletBinding()]
param(
    [string]
    $OutputPath = (Join-Path -Path $PSScriptRoot -ChildPath '.sample-credential-clixml')
)

try {
    if (-not (Test-Path -Path $OutputPath -PathType Container)) {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $CredentialPath = Join-Path -Path $OutputPath -ChildPath 'training-credential.xml'
    $SecurePassword = ConvertTo-SecureString -String 'SyntheticPassword-DoNotUse' -AsPlainText -Force
    $Credential = [pscredential]::new('TRAINING\svc-training', $SecurePassword)
    $Credential | Export-Clixml -Path $CredentialPath
    $ImportedCredential = Import-Clixml -Path $CredentialPath
    $IsWindowsHost = $PSVersionTable.Platform -eq 'Win32NT' -or $IsWindows

    [pscustomobject]@{
        Path = $CredentialPath.Replace($PSScriptRoot, '.')
        UserName = $ImportedCredential.UserName
        Platform = if ($IsWindowsHost) { 'Windows' } else { 'Non-Windows' }
        Portability = if ($IsWindowsHost) { 'Same user and computer' } else { 'PowerShell local protection only' }
        LiveDpapiProven = $false
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}

