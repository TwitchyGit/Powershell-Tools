<#
.SYNOPSIS
Shows comment-based help structure.

.DESCRIPTION
PowerShell reads this block through Get-Help. Help stays close to code so behavior and usage change together.
#>
[CmdletBinding()]
param()

try {
    Get-Help -Name $PSCommandPath | Select-Object -Property Synopsis
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
