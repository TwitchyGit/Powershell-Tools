[CmdletBinding()]
param()

try {
    $Objects = @(
        [pscustomobject]@{
            Name = 'training-safe-01'
            PlatformId = 'Training-Windows'
            Address = 'training-host-01'
            UserName = 'training.user'
        }
        [pscustomobject]@{
            Name = 'training-safe-02'
            PlatformId = 'Training-Linux'
            Address = 'training-host-02'
            UserName = 'training.service'
        }
    )

    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-training-data'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Path = Join-Path -Path $DataFolder -ChildPath 'pas-object-list.json'
    $Objects |
        ConvertTo-Json -Depth 4 |
        Set-Content -Path $Path -ErrorAction Stop

    $Objects

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
