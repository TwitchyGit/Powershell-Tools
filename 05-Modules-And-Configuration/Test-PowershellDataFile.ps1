<#
.SYNOPSIS
Shows PSD1 configuration validation.

.DESCRIPTION
The script validates required sections in local training configuration data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $EnvironmentPath = Join-Path -Path $PSScriptRoot -ChildPath 'Environment.psd1'
    $Environment = Import-PowerShellDataFile -Path $EnvironmentPath
    $RequiredSections = @('Repository', 'Paths', 'Deployment')
    $MissingSections = $RequiredSections |
        Where-Object { -not $Environment.ContainsKey($_) }

    [pscustomobject]@{
        Stage = 'ValidateDataFile'
        Path = $EnvironmentPath
        RepositoryName = $Environment.Repository.Name
        PackageName = $Environment.Deployment.PackageName
        EnvironmentName = $Environment.Deployment.EnvironmentName
        MissingSections = $MissingSections
        Passed = $MissingSections.Count -eq 0
    }

    if ($MissingSections.Count -gt 0) {
        Write-Error -Message 'Environment.psd1 is missing required sections.' -ErrorAction Stop
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
