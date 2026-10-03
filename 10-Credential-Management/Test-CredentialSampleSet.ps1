<#
.SYNOPSIS
Checks the credential-management training sample set.

.DESCRIPTION
The script parses credential-management scripts and validates the local fixture files.

.NOTES
The script performs local validation only. It does not test live credential providers.
#>
[CmdletBinding()]
param()

try {
    $ScriptFiles = Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1' -File |
        Where-Object { $_.Name -ne 'Test-CredentialSampleSet.ps1' } |
        Sort-Object -Property Name
    $ParseErrors = foreach ($ScriptFile in $ScriptFiles) {
        $Tokens = $null
        $Errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($ScriptFile.FullName, [ref]$Tokens, [ref]$Errors) |
            Out-Null
        foreach ($ErrorItem in $Errors) {
            [pscustomobject]@{
                File = $ScriptFile.Name
                Message = $ErrorItem.Message
            }
        }
    }

    $FixturePath = Join-Path -Path $PSScriptRoot -ChildPath 'fixtures/credential-samples.json'
    $ExpectedPath = Join-Path -Path $PSScriptRoot -ChildPath 'expected/credential-summary.json'
    $Fixture = Get-Content -Path $FixturePath -Raw | ConvertFrom-Json
    $Expected = Get-Content -Path $ExpectedPath -Raw | ConvertFrom-Json

    [pscustomobject]@{
        Scripts = $ScriptFiles.Count
        ParserErrors = @($ParseErrors).Count
        FixtureUsers = @($Fixture.Users).Count
        FixtureTokens = @($Fixture.Tokens).Count
        FixtureCertificates = @($Fixture.Certificates).Count
        ExpectedFailedScripts = $Expected.ExpectedFailedScripts
    }

    if ($ParseErrors) {
        $ParseErrors
        Write-Error -Message 'One or more credential-management scripts failed parser checks.' -ErrorAction Stop
    }

    exit 0
} catch {
    Write-Error -Message $_.Exception.Message
    exit 1
}
