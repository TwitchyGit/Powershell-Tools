<#
.SYNOPSIS
    Legacy sample patterns for the upgrade scanner.
.DESCRIPTION
    This file is scanned as sample input. The functions are not called by the training lesson.
#>
[CmdletBinding()]
param()

function Invoke-LegacyReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object] $Report
    )

    $Report | ConvertTo-Json | Set-Content -Path 'D:\Reports\legacy-report.json'
}

function Invoke-LegacyRemoteCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Server
    )

    Invoke-Command -ComputerName $Server -ScriptBlock {
        $PSVersionTable.PSVersion
    }
}

function Invoke-LegacyWindowsApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ComputerName
    )

    $Shell = New-Object -ComObject WScript.Shell
    $Computer = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $ComputerName
    [System.Web.HttpUtility]::UrlEncode($Computer.Caption)
    $Shell.CurrentDirectory
}

function Invoke-LegacyNativeTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Repository
    )

    git clone $Repository 'D:\Repo'
}

exit 0
