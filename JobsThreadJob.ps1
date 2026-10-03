[CmdletBinding()]
param()

try {
    # Thread job runs work in same process. Receive-Job collects serialized result.
    $Job = Start-ThreadJob -ScriptBlock {
        [pscustomobject]@{ Value = 21 * 2 }
    }

    Receive-Job -Job $Job -Wait -AutoRemoveJob
    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
