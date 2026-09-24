# Git repository training notes

These files model a Git deployment without using a real remote repository. The aim is to show where key setup,
package preparation and deployment invocation normally fit in a script chain.

## Sample sequence

1. `Setup-GitRepoKeys.ps1` creates placeholder key material in `.sample-git-keys`.
2. `Prepare-Deployment.ps1` creates a package manifest in `.sample-packages`.
3. `Invoke-Deployment.ps1` creates a deployment receipt in `.sample-deployments`.
4. `Deploy-GitRepository.ps1` runs the full sequence.

## Safety notes

- The sample keys are plain text placeholders.
- The sample token is format-checked only.
- The scripts do not call `git`, `ssh` or any network command.
- All generated sample state stays in this Code Samples directory.
