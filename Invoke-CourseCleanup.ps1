<#
.SYNOPSIS
Removes generated course sample output.

.DESCRIPTION
The script removes generated `.sample-*` folders from the Code Samples tree.

.NOTES
This script is training material. It removes only generated sample folders under the course root.
#>
[CmdletBinding(SupportsShouldProcess)]
param()

try {
    $CourseRoot = $PSScriptRoot
    $GeneratedItems = Get-ChildItem -Path $CourseRoot -Recurse -Directory -Force |
        Where-Object { $_.Name -like '.sample-*' } |
        Sort-Object -Property FullName

    foreach ($Item in $GeneratedItems) {
        if ($PSCmdlet.ShouldProcess($Item.FullName, 'Remove generated sample folder')) {
            Remove-Item -Path $Item.FullName -Recurse -Force -ErrorAction Stop
        }

        [pscustomobject]@{
            Path = $Item.FullName.Replace($CourseRoot, '.')
            Removed = -not (Test-Path -Path $Item.FullName)
        }
    }

    [pscustomobject]@{
        CheckedRoot = $CourseRoot
        GeneratedFolders = $GeneratedItems.Count
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
