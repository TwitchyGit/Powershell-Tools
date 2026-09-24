function Get-SampleRoot {
    [CmdletBinding()]
    param()

    $PSScriptRoot
}

function Join-SamplePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ChildPath
    )

    Join-Path -Path (Get-SampleRoot) -ChildPath $ChildPath
}

function Get-SampleEnvironment {
    [CmdletBinding()]
    param()

    $EnvironmentPath = Join-SamplePath -ChildPath 'Environment.psd1'
    Import-PowerShellDataFile -Path $EnvironmentPath
}

function New-SampleFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path -PathType Container)) {
        New-Item -Path $Path -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    Get-Item -Path $Path -Force -ErrorAction Stop
}

function Write-SampleLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $Environment = Get-SampleEnvironment
    $LogFolder = Join-SamplePath -ChildPath $Environment.Paths.LogFolder
    New-SampleFolder -Path $LogFolder | Out-Null

    $LogPath = Join-Path -Path $LogFolder -ChildPath 'training-deployment.log'
    $Entry = '{0:o} [{1}] {2}' -f (Get-Date), $Level, $Message
    Add-Content -Path $LogPath -Value $Entry -ErrorAction Stop

    [pscustomobject]@{
        LogPath = $LogPath
        Level = $Level
        Message = $Message
    }
}

function Test-SampleToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Token
    )

    $HasPrefix = $Token.StartsWith('sample_', [System.StringComparison]::Ordinal)
    $HasBody = $Token.Length -ge 16

    [pscustomobject]@{
        TokenLength = $Token.Length
        HasTrainingPrefix = $HasPrefix
        HasMinimumLength = $HasBody
        IsValid = $HasPrefix -and $HasBody
    }
}

Export-ModuleMember -Function Get-SampleRoot
Export-ModuleMember -Function Join-SamplePath
Export-ModuleMember -Function Get-SampleEnvironment
Export-ModuleMember -Function New-SampleFolder
Export-ModuleMember -Function Write-SampleLog
Export-ModuleMember -Function Test-SampleToken
