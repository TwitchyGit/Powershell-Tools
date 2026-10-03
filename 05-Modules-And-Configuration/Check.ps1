<#
.SYNOPSIS
Shows course-wide static validation.

.DESCRIPTION
The script parses course PowerShell files and imports shared modules.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $CourseRoot = Split-Path -Path $PSScriptRoot -Parent
    $Files = Get-ChildItem -Path $CourseRoot -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File |
        Sort-Object -Property FullName

    $ParseErrors = foreach ($File in $Files) {
        $Tokens = $null
        $Errors = $null

        [System.Management.Automation.Language.Parser]::ParseFile($File.FullName, [ref]$Tokens, [ref]$Errors) | Out-Null
        foreach ($ErrorItem in $Errors) {
            [pscustomobject]@{
                File = $File.FullName.Replace($CourseRoot, '.')
                Message = $ErrorItem.Message
            }
        }
    }

    if ($ParseErrors) {
        $ParseErrors
        Write-Error -Message 'One or more sample files failed parser checks.' -ErrorAction Stop
    }

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PSFunctions.psm1') -Force -ErrorAction Stop
    $DeploymentModule = Join-Path -Path $PSScriptRoot `
        -ChildPath '../06-Deployment-And-Git-Training/DeploymentFunctions.psm1'
    Import-Module -Name $DeploymentModule -Force -ErrorAction Stop

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
