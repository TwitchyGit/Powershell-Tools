[CmdletBinding()]
param(
    [string]$SafeName = 'Training-Large-Safe',

    [int]$AccountCount = 25
)

try {
    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-user-backup'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Accounts = for ($Index = 1; $Index -le $AccountCount; $Index++) {
        [pscustomobject]@{
            SafeName = $SafeName
            AccountName = 'training-account-{0:000}' -f $Index
            PlatformId = 'Training-Platform'
            Address = 'training-host-{0:000}' -f $Index
        }
    }

    $SafePath = Join-Path -Path $DataFolder -ChildPath 'large-safe-data.json'
    ConvertTo-Json -InputObject $Accounts -Depth 4 |
        Set-Content -Path $SafePath -ErrorAction Stop

    [pscustomobject]@{
        SafeName = $SafeName
        AccountCount = $AccountCount
        SafePath = $SafePath
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
