$Cred = Get-Credential
function Test-Start {
    param(
        [string]$Label,
        [string]$UserName,
        [string]$Domain,
        [bool]$Profile
    )
    $Si = [System.Diagnostics.ProcessStartInfo]::new('cmd.exe', '/c whoami')
    $Si.UserName = $UserName
    if ($Domain) { $Si.Domain = $Domain }
    $Si.Password = $Cred.Password.Copy()
    $Si.LoadUserProfile = $Profile
    $Si.UseShellExecute = $false
    $Si.RedirectStandardOutput = $true
    try {
        $P = [System.Diagnostics.Process]::Start($Si)
        "{0}: ok  {1}" -f $Label, $P.StandardOutput.ReadToEnd().Trim()
        $P.WaitForExit()
    } catch {
        "{0}: FAIL  {1}" -f $Label, $_.Exception.InnerException.Message
    }
}
$User = $Cred.UserName
if ($User -match '^(?<D>[^\\]+)\\(?<N>.+)$') {
    Test-Start 'split, no profile'   $Matches.N $Matches.D $false
    Test-Start 'split, profile'      $Matches.N $Matches.D $true
}
Test-Start 'raw name, no profile'    $User '' $false
Test-Start 'raw name, profile'       $User '' $true
