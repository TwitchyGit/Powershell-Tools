[CmdletBinding()]
param(
    [string]$GroupName = 'Training-Operators',

    [string]$MemberName = 'training.user'
)

try {
    $Result = [pscustomobject]@{
        GroupName = $GroupName
        MemberName = $MemberName
        Action = 'WouldAddMember'
        TrainingOnly = $true
    }

    $DataFolder = Join-Path -Path $PSScriptRoot -ChildPath '.sample-training-data'
    if (-not (Test-Path -Path $DataFolder -PathType Container)) {
        New-Item -Path $DataFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
    }

    $Path = Join-Path -Path $DataFolder -ChildPath 'group-member-sample.json'
    $Result |
        ConvertTo-Json -Depth 4 |
        Set-Content -Path $Path -ErrorAction Stop

    $Result

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
