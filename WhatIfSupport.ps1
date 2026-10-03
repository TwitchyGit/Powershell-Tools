[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$Name = 'DemoItem'
)

try {
    # ShouldProcess lets -WhatIf and -Confirm preview or gate changes.
    if ($PSCmdlet.ShouldProcess($Name, 'Show simulated change')) {
        [pscustomobject]@{
            Changed = $true
            Name = $Name
        }
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
