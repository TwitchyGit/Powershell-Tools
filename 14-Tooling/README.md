# CyberArk WPM: Raise a Case or Fix Internally

CyberArk hosts and configures the WPM tenant. We own everything between the user and the tenant: identity provider, provisioning, endpoints, browsers, extension deployment and network. This page sets out which issues go to CyberArk support and which stay with us.

## The rule

If a fault is limited to one user, device, browser or network, it is ours. A fault that began after a change on our side is also ours. If it affects many users across different devices and networks while our identity provider, provisioning and endpoints are healthy, it is the tenant or platform, so raise a case.

## Raise a case with CyberArk

| Issue | What it looks like |
|---|---|
| Tenant or admin portal unavailable | Tenant URL or admin portal fails or errors for all admins and users, our network checks are clean and the CyberArk status page does not explain it |
| Platform-wide login or autofill failure | Extension cannot sign in or retrieve items for many users on different devices and networks, while SSO to the tenant itself succeeds |
| Vault data or sync faults | Items missing, not saving, not syncing or shared items and folders not visible to users who have the correct membership |
| Tenant configuration we cannot change | Policy, feature enablement or tenant-level settings that are not available in our admin portal |
| Provisioning rejected by the tenant | Our identity provider sends valid requests and the tenant returns server errors or rejects them |
| Extension defect | Behaviour broke on a specific site or browser version after a vendor release and a clean browser profile does not fix it |
| Audit, reporting or export faults | Audit events, reports or exports missing or wrong |
| Suspected security impact | Unexpected admin changes in the audit log, signs of unauthorised tenant access or possible data exposure (involve internal security at the same time) |
| Data actions only CyberArk can do | Restore, deletion, tenant log requests or root cause analysis |
| Licence and entitlement | Seat counts, product changes, renewals |
| Product enhancement | Missing feature that blocks a requirement (raise as an enhancement request, not an incident) |

## Deal with internally

| Issue | Where to look |
|---|---|
| Single user cannot log in | Account locked or disabled in the identity provider, MFA device lost or reset needed, expired IdP session, password reset |
| SSO failures | Identity provider certificate expiry, assertion or claims mismatch, group claim changes, conditional access blocks, clock skew |
| User or group not in WPM | Group membership, provisioning scope, attribute mapping, joiner process |
| Extension missing, blocked or outdated | Intune or GPO deployment, browser policy, version pinning |
| Extension cannot reach the tenant | Proxy, firewall allowlist, TLS inspection, DNS, endpoint security software |
| Browser faults | Corrupt profile, cache, conflicting password manager or other extensions |
| Permissions and sharing we can set in the admin portal | Roles, shared folder membership, policy settings available to our admins |
| How-to and training questions | Existing documentation and vendor guides |
| Anything that began straight after one of our changes | Our change calendar, then roll back or correct |

If a setting can be changed in our admin portal, it is internal. If the portal does not offer it, it is a CyberArk request.

## Checks before raising a case

1. Check the CyberArk status page and any vendor notices for an open incident. If one exists, link our ticket to it and do not raise a duplicate.
2. Test with a second user, a second browser and a second network.
3. Test with a clean browser profile and the current extension version.
4. Confirm the identity provider, SSO and provisioning are healthy and nothing changed on our side recently.
5. Confirm the tenant URL resolves and is reachable without the proxy interfering.

## Information to attach to every case

- Tenant name or ID
- Number of users affected and whether they share a device type, network, browser or group
- First and latest occurrence with timestamps and timezone
- Browser, extension version and operating system
- Exact error text, screenshots and any correlation or request IDs
- HAR file or browser console output where the fault is in the extension or portal
- Results of the checks above and what has already been tried
