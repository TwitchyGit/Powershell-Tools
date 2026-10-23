$Cred = Get-Credential
$User = $Cred.UserName
$Name = $User
$Domain = ''
if ($User -match '^(?<D>[^\\]+)\\(?<N>.+)$') {
    $Name = $Matches.N
    $Domain = $Matches.D
}

function Test-Case {
    param(
        [string]$Label,
        [scriptblock]$Setup
    )
    $Si = [System.Diagnostics.ProcessStartInfo]::new('cmd.exe', '/c whoami')
    $Si.UseShellExecute = $false
    $Si.RedirectStandardOutput = $true
    $Si.WorkingDirectory = 'C:\Windows\System32'
    $Si.UserName = $Name
    if ($Domain) { $Si.Domain = $Domain }
    & $Setup $Si
    try {
        $P = [System.Diagnostics.Process]::Start($Si)
        "{0}: ok  {1}" -f $Label, $P.StandardOutput.ReadToEnd().Trim()
        $P.WaitForExit()
    } catch {
        "{0}: FAIL  {1}" -f $Label, $_.Exception.InnerException.Message
    }
}

# 1. Plain-text password skips the SecureString marshalling path
Test-Case 'clear-text password' { param($Si) $Si.PasswordInClearText = $Cred.GetNetworkCredential().Password }

# 2. Minimal environment block rules out a bad variable in the inherited one
Test-Case 'minimal environment' {
    param($Si)
    $Si.Password = $Cred.Password.Copy()
    $Si.Environment.Clear()
    $Si.Environment['SystemRoot'] = $env:SystemRoot
    $Si.Environment['Path'] = "$env:SystemRoot\System32"
}

# 3. Fixed working directory with the default SecureString
Test-Case 'fixed cwd only' { param($Si) $Si.Password = $Cred.Password.Copy() }

# 4. Windows API directly: is the logon itself allowed for this account on this host?
Add-Type -Namespace Win32 -Name Logon -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("advapi32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
public static extern bool LogonUser(string user, string domain, string password, int type, int provider, out System.IntPtr token);
[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern bool CloseHandle(System.IntPtr handle);
'@
foreach ($Type in 2, 3, 4) {
    $Token = [IntPtr]::Zero
    $Ok = [Win32.Logon]::LogonUser($Name, $(if ($Domain) { $Domain } else { $null }),
        $Cred.GetNetworkCredential().Password, $Type, 0, [ref]$Token)
    $Code = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
    "LogonUser type ${Type}: ok=$Ok win32error=$Code"
    if ($Ok) { [void][Win32.Logon]::CloseHandle($Token) }
}
