$SecureToken = Read-Host -AsSecureString -Prompt "GitLab API token"
$PlainToken  = [System.Net.NetworkCredential]::new("", $SecureToken).Password

$GitLabHost     = "gitlab.company.com"
$EncodedProject = "eis-cyberark_password_vault-onboarding-tools-eng%2FAD-Account-Monitor"
$ApiUri         = "https://$GitLabHost/api/v4/projects/$EncodedProject/deploy_keys"

try {
    $Result = Invoke-RestMethod -Method Get -Uri $ApiUri -Headers @{ "PRIVATE-TOKEN" = $PlainToken }
    Write-Output "SUCCESS"
    $Result | ConvertTo-Json
} catch {
    Write-Output "STATUS: $($_.Exception.Response.StatusCode.value__)"
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        Write-Output "BODY: $($_.ErrorDetails.Message)"
    } elseif ($_.Exception.Response) {
        $Stream = $_.Exception.Response.GetResponseStream()
        $Reader = New-Object System.IO.StreamReader($Stream)
        Write-Output "BODY: $($Reader.ReadToEnd())"
        $Reader.Close()
    }
}
