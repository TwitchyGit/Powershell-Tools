<#
.SYNOPSIS
Shows training key setup.

.DESCRIPTION
The script creates local placeholder key files and validates their presence.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DeploymentFunctions.psm1') -Force -ErrorAction Stop

    $KeyName = 'training_git_repo_key'
    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'KeyName'
        Value = $KeyName
        Passed = -not [string]::IsNullOrWhiteSpace($KeyName)
    }

    $Result = New-TrainingGitKey -KeyName $KeyName
    $Result

    [pscustomobject]@{
        Stage = 'Validate'
        Check = 'KeyFilesExist'
        Value = $Result.KeyName
        Passed = $Result.PrivateKeyExists -and $Result.PublicKeyExists
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
