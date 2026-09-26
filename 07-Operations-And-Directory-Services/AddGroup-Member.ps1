<#
.SYNOPSIS
Shows idempotent group-member action shape.

.DESCRIPTION
The script writes a local training audit record and validates the file.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$GroupName = 'Training-Operators',

    [string]$MemberName = 'training.user'
)

try {
    [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'GroupAndMember'
        GroupName = $GroupName
        MemberName = $MemberName
        Passed = -not [string]::IsNullOrWhiteSpace($GroupName) -and -not [string]::IsNullOrWhiteSpace($MemberName)
    }

    $Result = [pscustomobject]@{
        Stage = 'AddGroupMember'
        GroupName = $GroupName
        MemberName = $MemberName
        Action = 'WouldAddMember'
        AlreadyMember = $false
        AuditAction = 'RecordMembershipChange'
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

    [pscustomobject]@{
        Stage = 'Validate'
        GroupName = $Result.GroupName
        MemberName = $Result.MemberName
        Path = $Path
        Exists = Test-Path -Path $Path -PathType Leaf
        TrainingOnly = $true
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
