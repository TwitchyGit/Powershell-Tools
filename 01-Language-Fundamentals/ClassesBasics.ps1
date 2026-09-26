<#
.SYNOPSIS
Shows a basic PowerShell class.

.DESCRIPTION
The script creates a typed training object and reports method output from local sample data.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

class CourseItem {
    [string]$Name
    [int]$Level

    CourseItem([string]$Name, [int]$Level) {
        # Constructor sets required state so later methods can depend on valid values.
        $this.Name = $Name
        $this.Level = $Level
    }

    [string] Describe() {
        return "$($this.Name): level $($this.Level)"
    }
}

try {
    $Item = [CourseItem]::new('Pipeline', 2)
    [pscustomobject]@{
        Stage = 'ClassBasics'
        TypeName = $Item.GetType().Name
        Description = $Item.Describe()
        LevelIsValid = $Item.Level -gt 0
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
