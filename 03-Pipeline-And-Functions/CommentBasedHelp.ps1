<#
.SYNOPSIS
Shows comment-based help structure.

.DESCRIPTION
PowerShell reads this block through Get-Help. Help stays close to code so behavior and usage change together.
#>
[CmdletBinding()]
param()

try {
    $Help = Get-Help -Name $PSCommandPath

    [pscustomobject]@{
        Stage = 'InspectHelp'
        Synopsis = $Help.Synopsis
        HasDescription = -not [string]::IsNullOrWhiteSpace($Help.Description.Text)
        ExampleCount = @($Help.Examples.Example).Count
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
