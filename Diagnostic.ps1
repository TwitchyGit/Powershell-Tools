[CmdletBinding()]
param()

try {
    $Checks = @(
        [pscustomobject]@{
            Name = 'SampleFolder'
            Result = 'Pass'
            Detail = $PSScriptRoot
        }
        [pscustomobject]@{
            Name = 'PowerShellVersion'
            Result = 'Info'
            Detail = $PSVersionTable.PSVersion.ToString()
        }
        [pscustomobject]@{
            Name = 'TrainingScope'
            Result = 'Pass'
            Detail = 'No live service checks are performed.'
        }
    )

    $Checks

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
