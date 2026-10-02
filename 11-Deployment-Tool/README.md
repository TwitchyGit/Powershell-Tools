# Deployment tool training

This unit teaches a local, safe-by-default deployment orchestrator pattern in PowerShell 7.6.

The sample implements the design in `CHANGES29.md` as training code. It validates configuration before action,
uses one branch-resolution path for report-only and action modes, runs all host stages through one shared
execution path and writes structured report objects.

## Files

- `DeploymentTool.psm1`: reusable classes and functions.
- `Invoke-DeploymentTool.ps1`: entry script for report-only or simulated action runs.
- `Test-DeploymentTool.ps1`: local parser, fixture and decision-logic checks.
- `fixtures/deployment-tool-config.json`: synthetic environment, tool, host, branch and stage data.
- `expected/deployment-tool-summary.json`: expected local validation counts.

## Run order

1. Run `Test-DeploymentTool.ps1`.
2. Run `Invoke-DeploymentTool.ps1 -ReportOnly -Unattended`.
3. Inspect `.sample-state/deployment-report.json`.

## Safety boundary

This unit does not contact live hosts, Git remotes, package feeds, WinRM sessions or credential providers. It proves
local parser health, local configuration validation and local decision behavior only.

Live use needs separate Windows, remoting, credential, Git remote, package-source and target-host validation.
