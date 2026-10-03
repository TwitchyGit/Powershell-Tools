[CmdletBinding()]
param(
    [string]$UserName = 'training.user'
)

try {
    $Record = [pscustomobject]@{
        UserName = $UserName
        Role = 'TrainingOperator'
        Enabled = $true
    }

    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-training-data'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Path = Join-Path -Path $DataFolder -ChildPath 'training-user-configuration.json'
    $Record |
        ConvertTo-Json -Depth 4 |
        Set-Content -Path $Path -ErrorAction Stop

    $Record

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
