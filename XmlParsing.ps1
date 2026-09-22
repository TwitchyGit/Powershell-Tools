[CmdletBinding()]
param()

try {
    # XML cast creates an XmlDocument so nodes can be navigated as properties.
    [xml]$Document = '<course><topic name="Pipeline" level="2" /></course>'
    $Topic = $Document.course.topic

    [pscustomobject]@{
        Name = $Topic.name
        Level = [int]$Topic.level
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
