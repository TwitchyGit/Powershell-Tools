<#
.SYNOPSIS
Shows ShouldProcess support.

.DESCRIPTION
The script reports whether a simulated change would run.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Name = 'DemoItem'
)

try {
    # ShouldProcess lets -WhatIf and -Confirm preview or gate changes.
    if ($PSCmdlet.ShouldProcess($Name, 'Show simulated change')) {
        [pscustomobject]@{
            Stage = 'ShouldProcess'
            Changed = $true
            Name = $Name
            TrainingOnly = $true
        }
    } else {
        [pscustomobject]@{
            Stage = 'ShouldProcess'
            Changed = $false
            Name = $Name
            TrainingOnly = $true
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
