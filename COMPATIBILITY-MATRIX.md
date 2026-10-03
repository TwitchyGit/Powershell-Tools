# Compatibility matrix

This matrix separates local evidence from live platform validation.

| Area | Local macOS PowerShell 7 | Windows PowerShell 5.1 | Windows PowerShell 7 | Live AD | Live PVWA | AutoSys |
| --- | --- | --- | --- | --- | --- | --- |
| Parser checks | Covered by `Check.ps1` | Not covered | Not covered | Not applicable | Not applicable | Not applicable |
| Smoke tests | Covered by `Invoke-CourseSmokeTest.ps1` | Not covered | Not covered | Not applicable | Not applicable | Not applicable |
| File and object samples | Covered locally | Requires Windows run | Requires Windows run | Not applicable | Not applicable | Not applicable |
| AD-shaped samples | Local records only | Local records only | Local records only | Requires live validation | Not applicable | Not applicable |
| CyberArk-shaped samples | Local records only | Local records only | Local records only | Not applicable | Requires live validation | Not applicable |
| AutoSys runfile sample | File generation only | File generation only | File generation only | Not applicable | Not applicable | Requires scheduler validation |
| PowerShell 5.1 compatibility | Static checks only | Requires live run | Not applicable | Not applicable | Not applicable | Not applicable |
| Credential-management samples | Local simulation only | Requires live run for DPAPI and Credential Manager | Requires live run for DPAPI and Credential Manager | Requires live validation for AD identities | Requires live validation for vault retrieval | Requires job-account validation |

## Statement of evidence

A passing local run proves that scripts parse and selected samples execute in the local PowerShell host. It does not prove Windows-specific behavior, scheduler behavior, domain behavior or CyberArk API behavior.

