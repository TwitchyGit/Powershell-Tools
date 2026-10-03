# Scope and Module Variables

## Scope modifiers

| Modifier | Meaning |
|---|---|
| `$global:Name` | Session-wide. Visible everywhere. Persists after the script ends |
| `$script:Name` | Script file scope. In a `.psm1`, module scope |
| `$local:Name` | Current scope only. This is the default for plain assignment |
| `$private:Name` | Current scope only and hidden from child scopes |
| `$using:Name` | Value from the calling session, inside `Invoke-Command`, `Start-Job` or `ForEach-Object -Parallel` |

## Reading versus writing

A child scope can read parent variables. Assigning with a plain name creates a new local variable and leaves the parent unchanged.

```powershell
$Count = 0

function Add-One {
    [CmdletBinding()]
    param()

    $Count = $Count + 1
}

Add-One
$Count
```

`$Count` is still 0. Use `$script:Count = $script:Count + 1` to change the outer value.

## Module variables

In a `.psm1`, `$script:` means module scope. It is private to the module unless exported.

```powershell
$script:Env = "DEV"

function Set-DeployContext {
    [CmdletBinding()]
    param(
        [string]$Environment
    )

    $script:Env = $Environment
}

function Get-DeployContext {
    [CmdletBinding()]
    param()

    [PSCustomObject]@{ Env = $script:Env }
}

Export-ModuleMember -Function Set-DeployContext, Get-DeployContext
```

Export a variable only when needed:

```powershell
Export-ModuleMember -Function Get-DeployContext -Variable Configure
```

Rules:

- Once `Export-ModuleMember` appears, only what it lists is exported. List every public function.
- A `.psd1` manifest filters again through `FunctionsToExport` and `VariablesToExport`. Keep both in sync.
- Prefer getter and setter functions over exported variables. A caller cannot overwrite them by accident.
- A module loads once per session. Values persist until `Remove-Module` or `Import-Module -Force`. Reset state at the start of the entry script.
- Never keep a plain-text password in a module variable. Keep the `PSCredential` object.

## Scriptblocks defined in a module

A scriptblock created inside a module is bound to that module. When called from outside, it looks up variables in the module scope first, then global. It does not see variables in the caller's script.

Pass values as parameters instead:

```powershell
$script:Configure = @(
    @{ Dest = "D:\System-Checks\Install"; Command = {
        param($Ctx)
        .\Set-Configuration.ps1 -Env $Ctx.Env -ServiceAccount $Ctx.ServiceAccount
    } }
)
```

Caller:

```powershell
$Ctx = @{
    Env            = $Env
    ServiceAccount = $ServiceAccount
}

foreach ($Step in $Configure) {
    & $Step.Command $Ctx
}
```

Better still, return the list from a function so nothing is shared state:

```powershell
function Get-ConfigureStep {
    [CmdletBinding()]
    param()

    @(
        @{ Dest = "D:\System-Checks\Install"; Command = { param($Ctx) ... } }
    )
}
```

`.GetNewClosure()` freezes variable values at creation time, so use it only when the values already exist when the scriptblock is built.

## $using: with remote calls

```powershell
$Branch = "release-dev"
Invoke-Command -ComputerName $Server -ScriptBlock {
    git checkout $using:Branch
}
```

Without `$using:`, the remote session sees an empty `$Branch`. Only the value travels, so changes on the remote side do not come back.
