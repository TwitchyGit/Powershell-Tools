<#
.SYNOPSIS
Shows GUI input shape without creating a real window.

.DESCRIPTION
The script reports local training validation state for GUI-style input.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param(
    [string]$UserName = 'training.user'
)

try {
    $Preflight = [pscustomobject]@{
        Stage = 'Preflight'
        Check = 'GuiInput'
        Value = $UserName
        Passed = -not [string]::IsNullOrWhiteSpace($UserName)
    }

    $Result = [pscustomobject]@{
        Stage = 'CheckUserGui'
        UserName = $UserName
        WindowTitle = 'Training User Check'
        Status = 'WouldShowUserStatus'
        Enabled = $true
        CoreValidation = 'WouldReuseCliValidation'
        TrainingOnly = $true
    }

    Write-Output -InputObject $Preflight
    Write-Output -InputObject $Result

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
