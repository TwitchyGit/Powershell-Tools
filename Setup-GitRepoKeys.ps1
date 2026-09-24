[CmdletBinding()]
param()

try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DeploymentFunctions.psm1') -Force -ErrorAction Stop

    $Result = New-TrainingGitKey -KeyName 'training_git_repo_key'
    $Result

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
