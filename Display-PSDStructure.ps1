<#
.SYNOPSIS
    Reads a .psd1 file and displays its content in plain English, grouped by category.

.DESCRIPTION
    Parses a .psd1 file safely (no code execution) and renders every key/value
    pair it finds, at every depth, as an indented plain-English tree. Works on
    any .psd1 shape, a module manifest, a plain config hashtable, deeply
    nested tool/environment definitions, not just the standard manifest keys.

    Tries Import-PowerShellDataFile first (fast, built-in, restricted language).
    Falls back to a safe AST walk for files Import-PowerShellDataFile rejects, so
    the tool still works no matter what shape the .psd1 file takes.

.PARAMETER Path
    Path to the .psd1 file to read.

.EXAMPLE
    .\Get-Psd1Summary.ps1 -Path C:\Modules\MyModule\MyModule.psd1
#>

<#
================================================================================
HOW THIS CODE WORKS
================================================================================

This script reads a .psd1 file and prints its content as plain-English
sections instead of raw PowerShell syntax. A .psd1 file is a hashtable
literal (@{ Key = Value; ... }), so the parsing works on that real
structure, not on a custom or guessed file format.

PARSING LOGIC

1.  Primary parse (Get-Psd1Data):
     - Calls the built-in Import-PowerShellDataFile cmdlet.
     - This cmdlet evaluates the file in restricted language mode, so it
       returns a real hashtable without ever executing arbitrary code.
     - Covers essentially every real-world module manifest.

2.  Fallback parse (ConvertFrom-Psd1Ast / Convert-Psd1AstNode), only used
    when step 1 fails:
     - Parses the file into a PowerShell AST (abstract syntax tree) with
       [System.Management.Automation.Language.Parser]::ParseFile.
     - Walks the AST by hand: HashtableAst becomes an ordered hashtable,
       ArrayLiteralAst/ArrayExpressionAst become arrays, constant and
       string nodes become their literal value, $true/$false/$null
       resolve directly.
     - Anything not safe to resolve this way (a script block, a computed
       expression) is shown as its literal source text instead of being
       run, so the file is still summarized without ever calling
       Invoke-Expression or similar.

3.  Tree rendering (Write-Psd1Node), recursive, no hardcoded key list:
     - A key whose value is a plain scalar or an array of scalars prints
       as one "Key = Value" line at the current indent depth.
     - A key whose value is a nested hashtable prints as its own heading
       line, then every key inside it is rendered one indent level
       deeper, by calling Write-Psd1Node again on that hashtable. This is
       what lets the script handle any depth of nesting, Environments ->
       ENG -> ServerGroups -> 'System-Checks' -> PrimaryServer, the same
       way it handles a flat manifest.
     - A key whose value is an array that contains at least one
       hashtable (e.g. a Steps array of @{ Script; Args }) prints each
       element on its own "[index]" line, recursing into the ones that
       are hashtables and printing the rest inline.
     - Because every branch recurses through the same function, nothing
       in the file is silently dropped, unlike a fixed manifest-key list
       that only knows about keys it was told to expect in advance.

4.  Value formatting (Format-Psd1Value), scalars and scalar arrays only:
     - $null or blank becomes "(not set)".
     - Empty arrays become "(none)"; non-empty arrays join with ", ".

5.  Output (Write-Psd1Node itself):
     - Scalar rows at the same nesting level are aligned on "=" using
       the widest key name at that level.
     - Uses Write-Output only (no Write-Host), so the result is
       redirectable/pipeable.

================================================================================
HOW TO USE
================================================================================

    .\Get-Psd1Summary.ps1 -Path "C:\Modules\MyModule\MyModule.psd1"

    - Path: mandatory. Location of the .psd1 file to read.
    - Exit code 0 on success, 1 if the file is missing or cannot be
      parsed by either the primary or fallback method.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Path
)

function ConvertFrom-Psd1Ast {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $messages = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
        Write-Error -Message "Parse error in '$Path': $messages"
        return $null
    }

    $hashtableAst = $ast.Find({ param($node) $node -is [System.Management.Automation.Language.HashtableAst] }, $false)

    if (-not $hashtableAst) {
        Write-Error -Message "No top-level hashtable found in '$Path'."
        return $null
    }

    return (Convert-Psd1AstNode -Node $hashtableAst)
}

function Convert-Psd1AstNode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Node
    )

    # Hashtable values arrive wrapped in pipeline/command/paren nodes; unwrap down
    # to the real expression before checking its type.
    while ($true) {
        if ($Node -is [System.Management.Automation.Language.PipelineAst] -and $Node.PipelineElements.Count -eq 1) {
            $Node = $Node.PipelineElements[0]
            continue
        }
        if ($Node -is [System.Management.Automation.Language.CommandExpressionAst]) {
            $Node = $Node.Expression
            continue
        }
        if ($Node -is [System.Management.Automation.Language.ParenExpressionAst]) {
            $Node = $Node.Pipeline
            continue
        }
        break
    }

    if ($Node -is [System.Management.Automation.Language.HashtableAst]) {
        $result = [ordered]@{}
        foreach ($pair in $Node.KeyValuePairs) {
            $key = Convert-Psd1AstNode -Node $pair.Item1
            $result[[string]$key] = Convert-Psd1AstNode -Node $pair.Item2
        }
        return $result
    }

    if ($Node -is [System.Management.Automation.Language.ArrayLiteralAst]) {
        return @($Node.Elements | ForEach-Object { Convert-Psd1AstNode -Node $_ })
    }

    if ($Node -is [System.Management.Automation.Language.ArrayExpressionAst]) {
        if ($Node.SubExpression -and $Node.SubExpression.Statements) {
            $items = @()
            foreach ($statement in $Node.SubExpression.Statements) {
                $items += Convert-Psd1AstNode -Node $statement.PipelineElements[0].Expression
            }
            return $items
        }
        return @()
    }

    if ($Node -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
        return $Node.Value
    }

    if ($Node -is [System.Management.Automation.Language.ConstantExpressionAst]) {
        return $Node.Value
    }

    if ($Node -is [System.Management.Automation.Language.VariableExpressionAst]) {
        switch ($Node.VariablePath.UserPath) {
            'true' { return $true }
            'false' { return $false }
            'null' { return $null }
            default { return "`$$($Node.VariablePath.UserPath)" }
        }
    }

    # Anything else (script blocks, expressions) is not safe or not meaningful to
    # evaluate here; surface its literal source text instead of running it.
    return "<$($Node.GetType().Name): $($Node.Extent.Text.Trim())>"
}

function Get-Psd1Data {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        return Import-PowerShellDataFile -Path $Path -ErrorAction Stop
    } catch {
        Write-Warning -Message "Import-PowerShellDataFile could not read '$Path' directly ($($_.Exception.Message)). Falling back to safe parse."
        return ConvertFrom-Psd1Ast -Path $Path
    }
}

function Test-Psd1ArrayHasHashtable {
    [CmdletBinding()]
    param(
        $Value
    )

    foreach ($item in $Value) {
        if ($item -is [System.Collections.IDictionary]) {
            return $true
        }
    }
    return $false
}

function Test-Psd1Nested {
    [CmdletBinding()]
    param(
        $Value
    )

    if ($Value -is [System.Collections.IDictionary]) {
        return $true
    }
    if (($Value -is [array] -or $Value -is [System.Collections.IList]) -and (Test-Psd1ArrayHasHashtable -Value $Value)) {
        return $true
    }
    return $false
}

function Format-Psd1Value {
    [CmdletBinding()]
    param(
        $Value
    )

    if ($null -eq $Value) {
        return '(not set)'
    }

    if ($Value -is [array] -or $Value -is [System.Collections.IList]) {
        if ($Value.Count -eq 0) {
            return '(none)'
        }
        return ($Value -join ', ')
    }

    if ($Value -is [bool]) {
        return $Value.ToString()
    }

    $text = $Value.ToString()
    if ([string]::IsNullOrWhiteSpace($text)) {
        return '(not set)'
    }
    return $text
}

function Get-Psd1LeafCount {
    [CmdletBinding()]
    param(
        $Value
    )

    if ($Value -is [System.Collections.IDictionary]) {
        $count = 0
        foreach ($key in $Value.Keys) {
            $count += (Get-Psd1LeafCount -Value $Value[$key])
        }
        return $count
    }

    if (($Value -is [array] -or $Value -is [System.Collections.IList]) -and (Test-Psd1ArrayHasHashtable -Value $Value)) {
        $count = 0
        foreach ($item in $Value) {
            $count += (Get-Psd1LeafCount -Value $item)
        }
        return $count
    }

    return 1
}

function Write-Psd1Node {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data,

        [int]$Depth = 0
    )

    $indent = '    ' * $Depth
    $scalarKeys = @($Data.Keys | Where-Object { -not (Test-Psd1Nested -Value $Data[$_]) })
    $widest = 0
    if ($scalarKeys.Count -gt 0) {
        $widest = ($scalarKeys | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
    }

    foreach ($key in $Data.Keys) {
        $value = $Data[$key]

        if ($value -is [System.Collections.IDictionary]) {
            Write-Output "$indent$key"
            Write-Output "$indent$('-' * $key.Length)"
            Write-Psd1Node -Data $value -Depth ($Depth + 1)
            Write-Output ''
            continue
        }

        if (($value -is [array] -or $value -is [System.Collections.IList]) -and (Test-Psd1ArrayHasHashtable -Value $value)) {
            Write-Output "$indent$key"
            Write-Output "$indent$('-' * $key.Length)"
            $index = 0
            foreach ($item in $value) {
                if ($item -is [System.Collections.IDictionary]) {
                    Write-Output "$indent    [$index]"
                    Write-Psd1Node -Data $item -Depth ($Depth + 2)
                } else {
                    Write-Output "$indent    [$index] $(Format-Psd1Value -Value $item)"
                }
                $index++
            }
            Write-Output ''
            continue
        }

        Write-Output ("{0}{1,-$widest}  = {2}" -f $indent, $key, (Format-Psd1Value -Value $value))
    }
}

function Show-Psd1Summary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Data,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Write-Output ('=' * 72)
    Write-Output "  PSD1 FILE: $(Split-Path -Path $Path -Leaf)"
    Write-Output ('=' * 72)
    Write-Output ''

    Write-Psd1Node -Data $Data -Depth 0

    Write-Output ('=' * 72)
    Write-Output "  Total top-level keys: $($Data.Keys.Count)   |   Total leaf values: $(Get-Psd1LeafCount -Value $Data)"
    Write-Output ('=' * 72)
}

if (-not (Test-Path -Path $Path)) {
    Write-Error -Message "File '$Path' does not exist."
    exit 1
}

$data = Get-Psd1Data -Path $Path

if ($null -eq $data) {
    Write-Error -Message "Could not read '$Path' as a .psd1 file."
    exit 1
}

Show-Psd1Summary -Data $data -Path $Path

exit 0
