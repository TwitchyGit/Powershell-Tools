[CmdletBinding()]
param()

try {
    $EnvironmentPath = Join-Path -Path $PSScriptRoot -ChildPath 'Environment.psd1'
    $Environment = Import-PowerShellDataFile -Path $EnvironmentPath

    [pscustomobject]@{
        RepositoryName = $Environment.Repository.Name
        PackageName = $Environment.Deployment.PackageName
        EnvironmentName = $Environment.Deployment.EnvironmentName
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
