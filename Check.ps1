[CmdletBinding()]
param()

try {
    $Files = @(
        'Setup-GitRepoKeys.ps1'
        'Prepare-Deployment.ps1'
        'Invoke-Deployment.ps1'
        'Deploy-GitRepository.ps1'
        'PSFunctions.psm1'
        'DeploymentFunctions.psm1'
        'Test-DeployKey.ps1'
        'Test-PowershellDataFile.ps1'
        'Check.ps1'
    )

    $ParseErrors = foreach ($File in $Files) {
        $Path = Join-Path -Path $PSScriptRoot -ChildPath $File
        $Tokens = $null
        $Errors = $null

        [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$Tokens, [ref]$Errors) | Out-Null
        foreach ($ErrorItem in $Errors) {
            [pscustomobject]@{
                File = $File
                Message = $ErrorItem.Message
            }
        }
    }

    if ($ParseErrors) {
        $ParseErrors
        Write-Error -Message 'One or more sample files failed parser checks.' -ErrorAction Stop
    }

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PSFunctions.psm1') -Force -ErrorAction Stop
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'DeploymentFunctions.psm1') -Force -ErrorAction Stop

    [pscustomobject]@{
        CheckedFiles = $Files.Count
        ParserErrors = 0
        ModulesLoaded = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
