# Deployment and Git training

This unit models a deployment chain without touching a real remote repository.

Sequence:

1. `Setup-GitRepoKeys.ps1` checks the training key name, creates placeholder key material and confirms the key files exist.
2. `Prepare-Deployment.ps1` loads the shared environment, creates a package manifest and confirms the file was written.
3. `Invoke-Deployment.ps1` resolves the manifest path, writes a deployment receipt and confirms the receipt exists.
4. `Deploy-GitRepository.ps1` runs the full sequence and emits a final stage summary.

Generated evidence:

- `.sample-git-keys` contains training-only key files and a fingerprint.
- `.sample-packages` contains a PSD1 manifest with source file details and a simple digest.
- `.sample-deployments` contains a receipt with package, version, environment and result.
- `.sample-logs` contains timestamped stage messages.

Run:

```powershell
./Deploy-GitRepository.ps1
```

Validate the training token shape:

```powershell
./Test-DeployKey.ps1
```

Training aim: understand how setup, packaging and deployment entry scripts cooperate through shared helper functions and local state.
