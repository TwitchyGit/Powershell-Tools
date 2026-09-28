# Credential management training

This unit teaches credential handling patterns for PowerShell automation. The scripts use synthetic data by default and do not require live passwords, live tokens, AD, WinRM, CyberArk or Windows Credential Manager.

## Learning outcomes

- Identify credential forms used by PowerShell automation.
- Distinguish `SecureString`, `PSCredential`, token, certificate and vault-backed patterns.
- Explain when DPAPI-bound CLIXML works and when it fails.
- Redact secret values from logs, receipts and structured output.
- Separate local simulation from live Windows, WinRM, AD or vault validation.

## Script order

1. `PlainText-Risk.ps1`
2. `SecureString-Basics.ps1`
3. `PSCredential-Basics.ps1`
4. `Clixml-Dpapi-Credential.ps1`
5. `EnvironmentVariable-Secret.ps1`
6. `SecretManagement-Pattern.ps1`
7. `Token-Handling.ps1`
8. `Certificate-Credential.ps1`
9. `Windows-CredentialManager-Pattern.ps1`
10. `StartProcess-Credential-Forms.ps1`
11. `WinRM-Credential-Boundary.ps1`
12. `Credential-Decision-Matrix.ps1`
13. `Test-CredentialSampleSet.ps1`

## Safety boundary

The default scripts use local synthetic values. They do not prove live Windows DPAPI, EFS, Credential Manager, AD, WinRM, CyberArk, SecretManagement vault or certificate private-key behavior.

Live checks should be run only on a prepared Windows host with approved test credentials.
