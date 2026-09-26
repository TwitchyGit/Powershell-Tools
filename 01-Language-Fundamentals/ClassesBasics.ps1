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
    $Item.Describe()

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
