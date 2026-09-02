$configModulePath = Join-Path -Path $PSScriptRoot -ChildPath 'Config/ConfigModule.psm1'
Import-Module -Name $configModulePath -Force -ErrorAction Stop

$Domains = @($CybHumanUserScanConfig.Domains)
$ExcludePatterns = @($CybHumanUserScanConfig.ExcludePatterns)

$ExcludeRegex = $ExcludePatterns -join '|'

$Results = [System.Collections.Generic.List[PSObject]]::new()

foreach ($Domain in $Domains) {
    Write-Host "Querying domain: $Domain" -ForegroundColor Cyan

    try {
        $DomainDN = (Get-ADDomain -Server $Domain -ErrorAction Stop).DistinguishedName

        $UserOUs = Get-ADOrganizationalUnit -Server $Domain `
                       -SearchBase $DomainDN `
                       -SearchScope Subtree `
                       -Filter { Name -eq "Users" } `
                       -ErrorAction Stop

        foreach ($OU in $UserOUs) {
            Write-Host "  Searching OU: $($OU.DistinguishedName)" -ForegroundColor DarkCyan

            $Users = Get-ADUser -Server $Domain `
                                -SearchBase $OU.DistinguishedName `
                                -SearchScope Subtree `
                                -Filter { Enabled -eq $true } `
                                -Properties DisplayName, SamAccountName, EmailAddress,
                                            Department, Title, LastLogonDate,
                                            PasswordLastSet, DistinguishedName `
                                -ErrorAction Stop

            foreach ($User in $Users) {
                if ($User.SamAccountName -match $ExcludeRegex) { continue }

                $Results.Add([PSCustomObject]@{
                    Domain            = $Domain
                    SamAccountName    = $User.SamAccountName
                    DisplayName       = $User.DisplayName
                    EmailAddress      = $User.EmailAddress
                    Department        = $User.Department
                    Title             = $User.Title
                    LastLogonDate     = $User.LastLogonDate
                    PasswordLastSet   = $User.PasswordLastSet
                    DistinguishedName = $User.DistinguishedName
                })
            }
        }

        Write-Host "  Running total: $($Results.Count) users" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to query domain '$Domain': $_"
    }
}

Write-Host "`nTotal users found: $($Results.Count)" -ForegroundColor Yellow

$OutputPath = Join-Path -Path $CybHumanUserScanConfig.OutputDirectory -ChildPath "HumanUsers_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
$Results | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Host "Exported to: $OutputPath" -ForegroundColor Green
