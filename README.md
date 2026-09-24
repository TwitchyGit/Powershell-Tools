# PowerShell deployment training samples

This isolated sample set demonstrates a small Git-style deployment flow inside the Code Samples folder.
It does not connect to remotes, services or any repository outside this folder.

## Files

- `Environment.psd1` stores training configuration.
- `PSFunctions.psm1` contains shared path, config, log and token helpers.
- `DeploymentFunctions.psm1` contains sample key, package and deployment functions.
- `Setup-GitRepoKeys.ps1` creates training key files.
- `Prepare-Deployment.ps1` creates a deployment manifest.
- `Invoke-Deployment.ps1` reads the manifest and writes a receipt.
- `Deploy-GitRepository.ps1` runs setup, prepare and invoke as one sequence.
- `Test-Token.ps1` checks a sample token format.
- `Test-PowershellDataFile.ps1` proves the data file can be loaded.
- `Check.ps1` parses the PowerShell files and imports the modules.

## Training flow

Run the complete sample:

```powershell
./Deploy-GitRepository.ps1
```

Run the check script:

```powershell
./Check.ps1
```

The scripts create only local training state in hidden sample folders in this directory.
