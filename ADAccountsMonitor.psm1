function Get-TrainingAdComputer {
    [CmdletBinding()]
    param(
        [string]$OrganizationalUnit = 'OU=Training,DC=example,DC=invalid'
    )

    @(
        [pscustomobject]@{
            Name = 'TRAINING-SRV01'
            Enabled = $true
            DistinguishedName = 'CN=TRAINING-SRV01,{0}' -f $OrganizationalUnit
        }
        [pscustomobject]@{
            Name = 'TRAINING-SRV02'
            Enabled = $false
            DistinguishedName = 'CN=TRAINING-SRV02,{0}' -f $OrganizationalUnit
        }
    )
}

function Test-TrainingAdComputer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Computer
    )

    [pscustomobject]@{
        Name = $Computer.Name
        Enabled = [bool]$Computer.Enabled
        Status = if ($Computer.Enabled) { 'Ready' } else { 'DisabledTrainingObject' }
    }
}

Export-ModuleMember -Function Get-TrainingAdComputer
Export-ModuleMember -Function Test-TrainingAdComputer
