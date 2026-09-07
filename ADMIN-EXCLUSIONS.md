# Administrator regression exclusions

The following operations do not need to run in the routine CyberArk 14.2 API
regression pack. Most are better covered by a dedicated environment-specific
test because a generic automated call would change shared configuration, affect
a real endpoint or require optional infrastructure.

| Area not included | Why it is excluded from the routine pack |
|---|---|
| Existing user, Safe, member and account changes | The User/Safe suite already tests these contracts with disposable objects. Repeating changes against real objects adds risk without useful API coverage. |
| Account-group and linked-account lifecycles | These require a platform designed for grouping or dependency links plus additional disposable accounts. Add them only when those platform behaviours are part of the upgrade acceptance criteria. |
| CPM verify, reconcile and change-password operations | These require a reachable test target and can change an external credential. Test separately with a dedicated managed account. |
| Live PSM connection launch, session termination and recording retrieval | These need a reachable target or active session and may interrupt a user or expose sensitive recordings. |
| Platform import, update, activate, deactivate and delete | Platforms are shared configuration. A failed cleanup or replacement-style update can affect many accounts. Read-only platform routes are included. |
| PSM connection-component import or update | Connectors are shared configuration and usually contain environment-specific packages. Read-only connector inventory is included. |
| Authentication-method create, update or delete | A mistake can prevent administrators from signing in. The suite tests read-only authentication inventory. |
| LDAP directory and directory-mapping changes | These depend on external directory services and can change enterprise-wide authentication or provisioning. |
| Master Policy, options, themes and global configuration changes | These are Vault-wide settings whose effects extend beyond disposable test objects. |
| Dual-control request creation, approval and rejection | This requires an appropriately configured account, requester, approver and workflow. It belongs in an access-workflow test pack. |
| Discovery scans, onboarding rules and pending-account promotion | These need CPM scanner infrastructure and real or simulated targets. They are not deterministic in a generic Vault test. |
| PTA-specific configuration and event injection | PTA is optional and synthetic security events can trigger alerts or incident handling. Read-only health can be enabled where appropriate. |
| Vault DR, failover, replication, backup, restore and service-control operations | These are operational resilience procedures, not safe routine REST regression calls. |
| Component credential reset or rotation | These can break communication between CyberArk components and the Vault. |
| SSH public-key add or delete for real users | This changes a user's authentication material. Use a dedicated authentication test when SSH-key logon is in scope. |
| Account secret retrieval from existing accounts | It can disclose production secrets. The User/Safe suite retrieves only its generated disposable secret. |
| Safe ownership changes for existing administrators | Effective access can change immediately and cleanup cannot prove that cached or inherited access was unaffected. |
| Report generation endpoints introduced after 14.2 | They cannot be a valid 14.2 compatibility baseline. Add a version-specific pack after the upgrade target supports them. |
| Cloud-only, BYOK and personal-admin capabilities | They are not part of a standard self-hosted 14.2 PVWA baseline and vary by deployment model. |

These exclusions are deliberate safety and determinism boundaries. If one of
these areas is operationally important, add a separate opt-in suite with its own
test infrastructure, permissions, cleanup plan and expected side effects.
