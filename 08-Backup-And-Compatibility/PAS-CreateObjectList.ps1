<#
.SYNOPSIS
Shows PAS object list creation.

.DESCRIPTION
The script writes local candidate objects and reports duplicate count.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    $Objects = @(
        [pscustomobject]@{
            Name = 'training-safe-01'
            PlatformId = 'Training-Windows'
            Address = 'training-host-01'
            UserName = 'training.user'
            Action = 'Create'
        }
        [pscustomobject]@{
            Name = 'training-safe-02'
            PlatformId = 'Training-Linux'
            Address = 'training-host-02'
            UserName = 'training.service'
            Action = 'Create'
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

    [pscustomobject]@{
        Stage = 'CreateObjectList'
        ObjectCount = $Objects.Count
        DuplicateNames = @($Objects | Group-Object -Property Name | Where-Object { $_.Count -gt 1 }).Count
        Path = $Path
        Objects = $Objects
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
