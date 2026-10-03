<#
.SYNOPSIS
Shows XML node and attribute access.

.DESCRIPTION
The script reports attribute values from a local XML sample.

.NOTES
This script is training material. It uses local sample data unless a caller supplies another path.
#>
[CmdletBinding()]
param()

try {
    # XML cast creates an XmlDocument so nodes can be navigated as properties.
    [xml]$Document = '<course><topic name="Pipeline" level="2" /></course>'
    $Topic = $Document.course.topic

    [pscustomobject]@{
        Stage = 'XmlParse'
        Name = $Topic.name
        Level = [int]$Topic.level
        HasTopicNode = $null -ne $Topic
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
