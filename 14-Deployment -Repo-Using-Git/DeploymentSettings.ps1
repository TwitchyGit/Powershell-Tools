<#
.SYNOPSIS
    Supplies the package catalogue and environment values that drive refresh and setup runs.
#>

function Get-DeploymentCatalogue {
    <#
    .SYNOPSIS
        Keeps package identity in one checked catalogue before folders are touched.
    #>
    [CmdletBinding()]
    param()

    return @(
        [DeploymentPackage]::new('Repo1', 'group/repo1.git', 'C:\Repo1'),
        [DeploymentPackage]::new('Repo2', 'group/repo2.git', 'C:\Repo2'),
        [DeploymentPackage]::new('Repo3', 'group/repo3.git', 'C:\Repo3'),
        [DeploymentPackage]::new('Repo4', 'group/repo4.git', 'C:\Repo4'),
        [DeploymentPackage]::new('Repo5', 'group/repo5.git', 'C:\Repo5')
    )
}

function Get-EnvironmentProfile {
    <#
    .SYNOPSIS
        Maps each deployment environment to the branch, source and setup values it is allowed to use.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('NONPROD', 'PROD')]
        [string] $Env
    )

    switch ($Env) {
        'NONPROD' {
            return [EnvironmentProfile]::new(
                'NONPROD', 'development', 'SourceControl', $true, '1.0.0', '1.0.0', '1.0.0', 'NONPRODPOOL'
            )
        }
        'PROD' {
            return [EnvironmentProfile]::new(
                'PROD', 'production', 'SourceControl', $true, '1.0.0', '1.0.0', '1.0.0', 'PRODPOOL'
            )
        }
    }
}

function Test-DeploymentPath {
    <#
    .SYNOPSIS
        Rejects catalogue and operator paths that could escape the expected package area on drive C.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return ($Path -match '^C:\\[A-Za-z0-9_ .\\-]+$' -and $Path -notmatch '\.\.')
}

function Test-SourcePath {
    <#
    .SYNOPSIS
        Accepts only simple source-control paths that identify one group and one project.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $SourcePath
    )

    return ($SourcePath -match '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\.git$' -and $SourcePath -notmatch '\.\.')
}

function Get-CheckedCatalogue {
    <#
    .SYNOPSIS
        Returns only catalogue entries that are known, unique and safe to process.
    #>
    [CmdletBinding()]
    param(
        [string[]] $RepoName
    )

    $Catalogue = Get-DeploymentCatalogue
    $Errors = [System.Collections.Generic.List[string]]::new()
    $NameSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($Package in $Catalogue) {
        if ([string]::IsNullOrWhiteSpace($Package.Name)) {
            $Errors.Add('A catalogue entry has no name.')
        } elseif (-not $NameSet.Add($Package.Name)) {
            $Errors.Add("Package '$($Package.Name)' appears more than once in the catalogue.")
        }

        if (-not (Test-SourcePath -SourcePath $Package.SourcePath)) {
            $Errors.Add("Package '$($Package.Name)' has an invalid source path '$($Package.SourcePath)'.")
        }

        if (-not (Test-DeploymentPath -Path $Package.Folder)) {
            $Errors.Add("Package '$($Package.Name)' has an invalid folder '$($Package.Folder)'.")
        }
    }

    if ($Errors.Count -gt 0) {
        Write-Error -Message ($Errors -join [Environment]::NewLine) -ErrorAction Stop
    }

    if ($null -eq $RepoName -or $RepoName.Count -eq 0) {
        return $Catalogue
    }

    $Requested = $RepoName | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $KnownNames = $Catalogue.Name
    $Unknown = $Requested | Where-Object { $_ -notin $KnownNames }

    if ($Unknown.Count -gt 0) {
        $Message = "Unknown package name: $($Unknown -join ', '). Valid names: $($KnownNames -join ', ')."
        Write-Error -Message $Message -ErrorAction Stop
    }

    return $Catalogue | Where-Object { $_.Name -in $Requested }
}
