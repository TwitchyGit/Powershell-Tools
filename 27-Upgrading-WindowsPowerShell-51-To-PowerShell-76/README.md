# Upgrading from Windows PowerShell 5.1 to PowerShell 7.6+

This section teaches how to review and update Windows PowerShell 5.1 scripts for PowerShell 7.6+.

The upgrade work should be treated as a compatibility migration, not a search-and-replace exercise. PowerShell 7.6+
runs on .NET, uses a different executable, has different module availability and is often used cross-platform. A script
that parses in both versions can still fail because a module, API, provider, remoting endpoint or native command behaves
differently.

## How to use this section

Start with this README. Read each change area, compare the 5.1 and 7.6+ examples, then run the local lesson script to
see the same ideas returned as structured upgrade decisions.

Suggested workflow:

1. Identify the script entry point and its expected inputs.
2. Separate PowerShell language issues from Windows-only dependencies.
3. Replace deprecated or 5.1-only patterns with PowerShell 7.6+ equivalents.
4. Keep live checks separate from parser and fixture checks.
5. Run the updated script with local sample data before using any live service.

Expected output from this section is an upgrade decision for each script:

- `Ready`: code is already compatible with PowerShell 7.6+ for the tested path.
- `UpdateRequired`: syntax or behavior should be changed before running in 7.6+.
- `WindowsOnly`: code can run in 7.6+ only on Windows or only through a Windows compatibility path.
- `LiveValidationRequired`: static review is not enough because the result depends on AD, WinRM, COM, WMI, a provider,
  a certificate store, a remote service or native Windows behavior.

Run:

```powershell
pwsh -NoProfile -NonInteractive -File ./Invoke-UpgradeReadinessLesson.ps1
pwsh -NoProfile -NonInteractive -File ./Invoke-UpgradeReadinessLesson.ps1 -View Examples
pwsh -NoProfile -NonInteractive -File ./Invoke-UpgradeReadinessLesson.ps1 -View Checklist
```

The script reads `fixtures/sample-data.json` and returns structured objects. It does not run AD, WinRM, Git,
certificate-store or live web checks.

To scan an existing Windows PowerShell 5.1 code directory, run:

```powershell
pwsh -NoProfile -NonInteractive -File ./Test-UpgradeReadiness.ps1 -Path ./LegacyScripts
pwsh -NoProfile -NonInteractive -File ./Test-UpgradeReadiness.ps1 -Path ./LegacyScripts -Format Json
pwsh -NoProfile -NonInteractive -File ./Test-UpgradeReadiness.ps1 -Path ./LegacyScripts -IncludeWrapperFiles
```

`Test-UpgradeReadiness.ps1` is read-only. It scans `.ps1`, `.psm1` and `.psd1` files and lists upgrade findings with:

- `File`
- `Line`
- `Pattern`
- `Decision`
- `Action`
- `Evidence`

Use the report as a worklist. It tells you what needs review, not what is proven fixed. Any finding marked
`LiveValidationRequired` still needs a controlled test on the correct Windows, remoting, Git or service boundary.

To save a JSON report:

```powershell
pwsh -NoProfile -NonInteractive -File ./Test-UpgradeReadiness.ps1 `
    -Path ./LegacyScripts `
    -IncludeWrapperFiles `
    -Format Json `
    -OutputPath ./upgrade-readiness.json
```

To try the scanner against the included legacy sample:

```powershell
pwsh -NoProfile -NonInteractive -File ./Test-UpgradeReadiness.ps1 `
    -Path ./fixtures/legacy-code-sample `
    -IncludeWrapperFiles
```

The scanner currently checks for:

- old runtime launchers such as `powershell.exe`
- host-only output
- Active Directory command and module boundaries
- remoting endpoint assumptions
- missing JSON depth
- missing file encoding
- web cmdlet review points
- WMI and COM usage
- scheduled-job cmdlets
- native command boundaries
- TLS framework overrides
- Windows path assumptions
- module manifests without `CompatiblePSEditions`
- wrapper files when `-IncludeWrapperFiles` is used

Scanner limits:

- It is a static scanner and does not prove runtime behavior.
- It does not import scanned modules.
- It does not run scanned scripts.
- It does not replace Windows, AD, WinRM, Git, COM, WMI or web-service validation.
- It reports likely upgrade work, then a person decides the actual code change.

## Why the scanner uses AST

AST means Abstract Syntax Tree. It is PowerShell's parsed structure for a script.

Plain text scanning treats a script as lines of text. That can create false findings when a word appears inside a
comment, string or scanner rule. AST scanning lets the script inspect actual PowerShell syntax.

For example, this line:

```powershell
Set-Content -Path ./report.json -Value $Json
```

PowerShell's parser can identify:

- command name: `Set-Content`
- parameter: `Path`
- parameter: `Value`
- variable: `$Json`
- source line number

That lets `Test-UpgradeReadiness.ps1` ask more precise questions:

- Is the command actually `Write-Host`?
- Is the command actually `ConvertTo-Json`?
- Does `ConvertTo-Json` have a `-Depth` parameter?
- Does `Set-Content` have an `-Encoding` parameter?
- Is `New-Object` being used with `-ComObject`?

The scanner still uses plain text checks for wrapper files such as `.cmd`, `.bat`, `.yml` and `.xml`, because those
files are not PowerShell syntax.

## Terms

- `powershell.exe`: Windows PowerShell 5.1 executable.
- `pwsh`: PowerShell 7+ executable.
- Windows PowerShell 5.1: built into Windows and based on .NET Framework.
- PowerShell 7.6+: current cross-platform PowerShell based on modern .NET.
- WindowsCompatibility: importing some Windows PowerShell modules into a compatibility session from PowerShell 7.

## Main change areas

### Runtime executable

Windows PowerShell scripts often relaunch themselves with `powershell.exe`. In PowerShell 7.6+, use `pwsh`.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Deploy.ps1
```

PowerShell 7.6+:

```powershell
pwsh -NoProfile -NonInteractive -File ./Deploy.ps1
```

Review questions:

- Does the script assume `powershell.exe` is the right engine?
- Does it need `-NonInteractive` for unattended jobs?
- Does the scheduler, AutoSys job or wrapper call the correct executable?

### Version checks

Avoid checking only the major version when the script depends on PowerShell 7 behavior.

Windows PowerShell 5.1:

```powershell
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error -Message 'PowerShell 5 or later is required'
    exit 1
}
```

PowerShell 7.6+:

```powershell
$MinimumVersion = [version] '7.6'
if ($PSVersionTable.PSVersion -lt $MinimumVersion) {
    Write-Error -Message "PowerShell $MinimumVersion or later is required"
    exit 1
}
```

Expected result:

- 5.1 script accepts Windows PowerShell 5.1 and later.
- 7.6+ script explicitly rejects older engines before using newer behavior.

### Module availability

Some Windows PowerShell modules are not native PowerShell 7 modules.

Windows PowerShell 5.1:

```powershell
Import-Module ActiveDirectory -ErrorAction Stop
Get-ADUser -Identity $SamAccountName
```

PowerShell 7.6+:

```powershell
if ($IsWindows) {
    Import-Module ActiveDirectory -UseWindowsPowerShell -ErrorAction Stop
    Get-ADUser -Identity $SamAccountName
} else {
    Write-Error -Message 'ActiveDirectory module requires a Windows validation host.' -ErrorAction Stop
}
```

Review questions:

- Is the module available natively in PowerShell 7?
- Does the script need `-UseWindowsPowerShell`?
- Does the output cross a remoting or compatibility boundary as deserialized objects?

### Encoding

Windows PowerShell 5.1 defaults differ from PowerShell 7.6+. Be explicit when files are shared with other systems.

Windows PowerShell 5.1:

```powershell
$Rows | Export-Csv -Path .\report.csv -NoTypeInformation
Set-Content -Path .\result.txt -Value $Message
```

PowerShell 7.6+:

```powershell
$Rows | Export-Csv -Path ./report.csv -NoTypeInformation -Encoding utf8
Set-Content -Path ./result.txt -Value $Message -Encoding utf8
```

Expected result:

- Text output is predictable across PowerShell versions.
- CSV and text files open correctly in downstream tools.

### Paths

Avoid hard-coded separators and drive assumptions when the script may run in PowerShell 7 outside Windows.

Windows PowerShell 5.1:

```powershell
$LogPath = "$PSScriptRoot\Logs\$RunId.log"
```

PowerShell 7.6+:

```powershell
$LogPath = Join-Path -Path $PSScriptRoot -ChildPath 'Logs' |
    Join-Path -ChildPath "$RunId.log"
```

Review questions:

- Does the script assume `C:` or `D:` exists?
- Does it build paths by string interpolation?
- Does it pass Windows paths into a native tool that expects different quoting?

### Native command errors

PowerShell 7 has stronger native-command behavior options. Do not confuse PowerShell success with native process
success.

Windows PowerShell 5.1:

```powershell
git clone $Repository $TargetPath
if ($LASTEXITCODE -ne 0) {
    Write-Error -Message 'Git clone failed'
    exit 1
}
```

PowerShell 7.6+:

```powershell
$NativeOutput = & git clone $Repository $TargetPath 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Error -Message "Git clone failed with exit code $LASTEXITCODE. $NativeOutput"
    exit 1
}
```

Expected result:

- The script records native output.
- The script exits `1` when the native tool fails.
- The script does not treat parser success as command success.

### Error handling

Use terminating errors at function boundaries when the caller needs `try/catch` to work.

Windows PowerShell 5.1:

```powershell
Copy-Item -Path $Source -Destination $Destination
if (-not $?) {
    Write-Error -Message 'Copy failed'
}
```

PowerShell 7.6+:

```powershell
Copy-Item -Path $Source -Destination $Destination -ErrorAction Stop
```

Entry script pattern:

```powershell
try {
    Copy-Item -Path $Source -Destination $Destination -ErrorAction Stop
    exit 0
} catch {
    Write-Error -Message "Copy failed. $($_.Exception.Message)"
    exit 1
}
```

Expected result:

- Recoverable failure can be caught by the caller.
- Entry script owns final user-facing error and final exit code.

### Remoting

Windows PowerShell 5.1 remoting examples often assume Windows PowerShell endpoints.

Windows PowerShell 5.1:

```powershell
Invoke-Command -ComputerName $Server -ScriptBlock {
    $PSVersionTable.PSVersion
}
```

PowerShell 7.6+:

```powershell
Invoke-Command -ComputerName $Server -ConfigurationName PowerShell.7 -ScriptBlock {
    $PSVersionTable.PSVersion
}
```

Review questions:

- Is a PowerShell 7 endpoint registered on the remote host?
- Does the remote host have the needed modules installed for PowerShell 7?
- Is the object returned by remoting deserialized?

Static checks cannot prove live remoting behavior.

### Scheduled execution

Update scheduled tasks, AutoSys jobs, service wrappers and batch files to call the intended engine.

Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File D:\Jobs\Refresh.ps1
```

PowerShell 7.6+:

```powershell
pwsh -NoProfile -NonInteractive -File C:\Jobs\Refresh.ps1
```

Review questions:

- Is `pwsh` on the service account `PATH`?
- Does the service account have the same module paths?
- Does the job rely on a mapped drive?
- Is the working directory explicit?

### Classes and modules

PowerShell class loading is sensitive to parse-time visibility. Prefer a module loaded with `using module` for classes
that depend on each other.

Windows PowerShell 5.1:

```powershell
. $PSScriptRoot\Classes\ServerPlan.ps1
. $PSScriptRoot\Classes\DeploymentPlan.ps1
```

PowerShell 7.6+:

```powershell
using module ./Classes/DeploymentTool.Classes.psm1
```

Expected result:

- Dependent classes are visible at parse time.
- Entry scripts have one clear class-module import.

### JSON depth

`ConvertTo-Json` needs explicit depth for nested objects in both versions.

Windows PowerShell 5.1:

```powershell
$Report | ConvertTo-Json | Set-Content -Path .\report.json
```

PowerShell 7.6+:

```powershell
$Report |
    ConvertTo-Json -Depth 10 |
    Set-Content -Path ./report.json -Encoding utf8
```

Expected result:

- Nested data is not silently flattened or truncated.
- Output encoding is explicit.

### TLS and web requests

Old scripts may force TLS settings for Windows PowerShell 5.1. Review whether that code still belongs in PowerShell
7.6+.

Windows PowerShell 5.1:

```powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-RestMethod -Uri $Uri -Headers $Headers
```

PowerShell 7.6+:

```powershell
$Response = Invoke-RestMethod -Uri $Uri -Headers $Headers -ErrorAction Stop
```

Review questions:

- Is certificate validation still enabled?
- Are retries, 401 handling and content-type checks documented?
- Are tokens redacted from logs?

### Null handling

PowerShell 7 supports operators that make defaulting clearer.

Windows PowerShell 5.1:

```powershell
if ($null -eq $Config.TimeoutSeconds) {
    $TimeoutSeconds = 30
} else {
    $TimeoutSeconds = $Config.TimeoutSeconds
}
```

PowerShell 7.6+:

```powershell
$TimeoutSeconds = $Config.TimeoutSeconds ?? 30
```

Expected result:

- Defaults are explicit.
- `$null` checks are easier to read.

### Parallel execution

PowerShell 7 has `ForEach-Object -Parallel`, but not every loop should become parallel.

Windows PowerShell 5.1:

```powershell
foreach ($Server in $ServerList) {
    Test-ServerState -Server $Server
}
```

PowerShell 7.6+:

```powershell
$ServerList | ForEach-Object -Parallel {
    Test-ServerState -Server $_
} -ThrottleLimit 5
```

Review questions:

- Does the code mutate shared state?
- Is output order important?
- Are imported modules available inside each runspace?
- Is the live system safe to query in parallel?

### Output and logging

Replace host-only output with redirectable streams and structured result objects.

Windows PowerShell 5.1:

```powershell
Write-Host "Deploying $PackageName"
```

PowerShell 7.6+:

```powershell
Write-Information -MessageData "Deploying $PackageName"
[pscustomobject]@{
    PackageName = $PackageName
    Stage = 'Deploy'
    Result = 'Started'
}
```

Expected result:

- Automation receives objects.
- Humans can still opt into information output.
- Logs can redact sensitive values before writing.

## Upgrade checklist

Use this checklist for each script.

- Entry point uses `pwsh` where PowerShell 7.6+ is required.
- Script starts with `[CmdletBinding()]` before `param(...)`.
- Parameters have validation where practical.
- Output is structured objects, not only formatted text.
- Secrets are never written in plain text.
- `Write-Host` has been replaced with redirectable output.
- Native command exit codes are checked.
- File encoding is explicit where files cross system boundaries.
- Paths use `Join-Path` or provider-aware APIs.
- JSON output uses an explicit `-Depth`.
- Windows-only modules and providers are named as Windows boundaries.
- Remoting endpoints are named when PowerShell 7 is required remotely.
- Parser checks, fixture checks and live checks are reported separately.
- Entry scripts exit `0` for success and `1` for failure.

## Runnable lesson script

This section stays small. A single script reads local examples and classifies upgrade work:

```powershell
pwsh -NoProfile -NonInteractive -File ./Invoke-UpgradeReadinessLesson.ps1
pwsh -NoProfile -NonInteractive -File ./Invoke-UpgradeReadinessLesson.ps1 -View Examples
```

Expected script output:

- `Pattern`: the migration issue being demonstrated.
- `WindowsPowerShell51`: the older pattern.
- `PowerShell76`: the updated pattern.
- `Decision`: `Ready`, `UpdateRequired`, `WindowsOnly` or `LiveValidationRequired`.
- `Reason`: why the migration decision was chosen.

The script uses local fixture data only and does not run AD, WinRM, Git, certificate-store or live web checks.

`Test-UpgradeReadiness.ps1` is the practical directory scanner for real legacy code. It reads the target directory and
returns a review worklist. It does not import, execute or modify the scanned code.
