<#
.SYNOPSIS
    Provides shared objects used to keep deployment decisions explicit and testable.
#>

class DeploymentPackage {
    [string] $Name
    [string] $SourcePath
    [string] $Folder

    DeploymentPackage([string] $Name, [string] $SourcePath, [string] $Folder) {
        $this.Name = $Name
        $this.SourcePath = $SourcePath
        $this.Folder = $Folder
    }
}

class EnvironmentProfile {
    [string] $Name
    [string] $Branch
    [string] $PackageSource
    [bool] $RequiresSourceCredential
    [string] $VersionOne
    [string] $VersionTwo
    [string] $VersionThree
    [string] $BackupPool

    EnvironmentProfile(
        [string] $Name,
        [string] $Branch,
        [string] $PackageSource,
        [bool] $RequiresSourceCredential,
        [string] $VersionOne,
        [string] $VersionTwo,
        [string] $VersionThree,
        [string] $BackupPool
    ) {
        $this.Name = $Name
        $this.Branch = $Branch
        $this.PackageSource = $PackageSource
        $this.RequiresSourceCredential = $RequiresSourceCredential
        $this.VersionOne = $VersionOne
        $this.VersionTwo = $VersionTwo
        $this.VersionThree = $VersionThree
        $this.BackupPool = $BackupPool
    }
}

class OperationResult {
    [bool] $Succeeded
    [string[]] $Messages

    OperationResult([bool] $Succeeded, [string[]] $Messages) {
        $this.Succeeded = $Succeeded
        $this.Messages = $Messages
    }
}

class InputValidationResult {
    [bool] $IsValid
    [string[]] $Errors

    InputValidationResult([string[]] $Errors) {
        $this.Errors = $Errors
        $this.IsValid = ($Errors.Count -eq 0)
    }
}
