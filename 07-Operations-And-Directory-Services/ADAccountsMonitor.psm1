<#
.SYNOPSIS
Provides local AD-shaped computer training functions.

.DESCRIPTION
The module returns sample computer records and classifies them without live AD access.

.NOTES
This module is training material. It uses local sample data unless a caller supplies another path.
#>
function Get-TrainingAdComputer {
    [CmdletBinding()]
    param(
        [string]$OrganizationalUnit = 'OU=Training,DC=example,DC=invalid'
    )

    @(
        [pscustomobject]@{
            Name = 'TRAINING-SRV01'
            Enabled = $true
            LastLogonDays = 3
            Owner = 'TrainingOps'
            DistinguishedName = 'CN=TRAINING-SRV01,{0}' -f $OrganizationalUnit
        }
        [pscustomobject]@{
            Name = 'TRAINING-SRV02'
            Enabled = $false
            LastLogonDays = 40
            Owner = ''
            DistinguishedName = 'CN=TRAINING-SRV02,{0}' -f $OrganizationalUnit
        }
        [pscustomobject]@{
            Name = 'TRAINING-SRV03'
            Enabled = $true
            LastLogonDays = 95
            Owner = 'TrainingDBA'
            DistinguishedName = 'CN=TRAINING-SRV03,{0}' -f $OrganizationalUnit
        }
    )
}

function Test-TrainingAdComputer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Computer
    )

    $Status = if (-not $Computer.Enabled) {
        'DisabledTrainingObject'
    } elseif ($Computer.LastLogonDays -gt 60) {
        'StaleTrainingObject'
    } elseif ([string]::IsNullOrWhiteSpace($Computer.Owner)) {
        'MissingOwner'
    } else {
        'Ready'
    }

    [pscustomobject]@{
        Name = $Computer.Name
        Enabled = [bool]$Computer.Enabled
        LastLogonDays = $Computer.LastLogonDays
        Owner = $Computer.Owner
        Status = $Status
        DistinguishedName = $Computer.DistinguishedName
    }
}

Export-ModuleMember -Function Get-TrainingAdComputer
Export-ModuleMember -Function Test-TrainingAdComputer
