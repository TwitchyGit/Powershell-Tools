# CyberArk SCIM Integration with ServiceNow

Consolidated notes from architecture discussion covering CyberArk PAM (on-prem, incl. isolated REGIONAL vault) integrating via SCIM with ServiceNow (assumed SaaS) for safe/user/secret management, tied to CMDB application records.

---

## 1. Objective

- Use SCIM (on-prem CyberArk SCIM server, and/or CyberArk Identity SaaS tenant) to manage Safes, Users, and permissions in CyberArk PAM.
- All safe/user onboarding and offboarding requests are initiated by ServiceNow.
- Safe creation driven by templates (safe type + group permission set).
- Users onboard to an application in ServiceNow and are added to a SCIM group granting **read** or **read/write** on the corresponding safe(s).
- Safes carry CMDB metadata (application reference, ServiceNow/Saviynt reference) so the CMDB-to-safe relationship is traceable.
- CyberArk environment includes an **isolated REGIONAL vault** with its own network constraints and likely its own data residency requirements.
- SCIM access must be restricted to specific LDAP branches and safe groups — safe creation normally requires a highly privileged (near-admin) CyberArk account, which is a core risk to manage.

---

## 2. Key Findings

- CyberArk's Identity SCIM server supports a **PAM extension** (`Containers`, `ContainerPermissions`, `PrivilegedData`) purpose-built for managing safes and permissions via SCIM, in addition to standard `Users`/`Groups`.
- The SCIM service account **requires the Vault Management administrative right** — there is no built-in narrower role for this. This is the single biggest structural risk in the design and needs compensating controls (see Architecture, below).
- A given SCIM configuration can target **Privilege Cloud or self-hosted PAM, not both** — relevant if scope ever expands beyond self-hosted.
- The PAM SCIM extension is based on an **IETF draft spec**, not the ratified SCIM 2.0 core — vendor implementation details matter more than the spec itself, and different SCIM clients may support different subsets of it.
- ServiceNow's commonly-referenced "native SCIM provisioning" is very likely **inbound** — ServiceNow acting as the SCIM *service provider* so an external IdP (Entra ID, Okta) can provision accounts *into* ServiceNow. That's the opposite of what's needed here. In this design, **ServiceNow must act as the SCIM client**, calling out to CyberArk's SCIM server. Whether ServiceNow has a generic outbound/SCIM-client capability (vs. needing custom IntegrationHub/Flow Designer work) is an open question for their team.

---

## 3. SCIM Protocol — High-Level Overview

**What it is:** IETF standard (SCIM 2.0, RFC 7643/7644) for automating identity provisioning/deprovisioning between systems via REST/JSON. Defines standard resource schemas (User, Group) and CRUD operations, extensible via vendor schemas.

**Core features**
- Standard User/Group schemas, extensible — CyberArk adds Container/ContainerPermission/PrivilegedData for PAM.
- CRUD via REST (GET/POST/PUT/PATCH/DELETE) against endpoints like `/Users`, `/Groups`, `/Containers`.
- Discovery endpoints (`/Schemas`, `/ResourceTypes`, `/ServiceProviderConfig`) to introspect what's actually supported.
- Filtering, pagination, sorting on GET; optional bulk operations endpoint.
- OAuth2 client-credentials or mTLS for machine-to-machine auth.
- Deprovisioning usually via soft `active: false` rather than hard delete, though both exist.

**General concerns to review**
- **Partial implementations** — most vendors implement a subset; verify supported operations/resources rather than assuming.
- **No built-in approval logic** — SCIM is transport only; all governance/approval workflow must live outside it (ServiceNow/IGA).
- **No fine-grained authorization model** — security depends entirely on how the endpoint and account are protected, not the protocol itself.
- **Drift / eventual consistency** — missed calls or failed retries silently desync source and target; needs a reconciliation job.
- **Idempotency varies by vendor** — retried/partial-failure behavior must be tested, not assumed.
- **Attribute/schema mismatches** — "group," "active," "deleted" may not mean the same thing on both sides.
- **Soft vs. hard delete semantics** — confirm behavior for offboarding and rehire scenarios.
- **Group-based vs. direct-entitlement models** — confirm both sides use the same assignment model.
- **Thin audit context by default** — request context (who/why/approval ref) must be carried as custom attributes or logged out-of-band.
- **Credential blast radius** — one compromised SCIM token/cert spans the whole integration scope.
- **Uni-directional by default** — manual changes made directly in CyberArk won't flow back to ServiceNow without a separate reconciliation mechanism.
- **Network dependency** — synchronous calls; unreachable endpoints (e.g., isolated REGIONAL) need defined retry/backlog handling.

**Concerns specific to this deployment**
- Safe creation via SCIM is inherently higher-risk (structural/destructive) than user/group operations — mitigate with templates and an indirection layer (see below).
- The Vault Management privilege requirement for the SCIM service account is the top item for the internal risk register.

---

## 4. Architecture Options

**Core components:** CyberArk on-prem self-hosted PAM (main + isolated REGIONAL vaults); CyberArk Identity (SaaS tenant hosting SCIM, or on-prem components/connector); ServiceNow (SCIM client, assumed SaaS); optional indirection/middleware layer.

### Option 1 — CyberArk Identity SaaS tenant hosts SCIM for everything
ServiceNow calls the CyberArk Identity SaaS tenant's SCIM endpoint (directly or via IntegrationHub); the tenant reaches on-prem vault(s) via CyberArk's on-prem connector.
- Simplest single integration point for ServiceNow.
- Doesn't solve REGIONAL isolation alone — isolated vault still needs its own connector with outbound connectivity to the SaaS tenant, which may not be permitted.
- All PAM metadata/traffic transits CyberArk's SaaS tenant — check against data residency requirements.

### Option 2 — On-prem SCIM server(s), one per region
Run CyberArk's SCIM server on-prem in each region. ServiceNow reaches each via a MID Server (preferred — outbound-only, no inbound firewall holes) or a WAF-fronted public endpoint (less desirable).
- Most defensible for the isolated REGIONAL environment and data residency.
- Two+ SCIM deployments to build, secure, and maintain.
- Key question for ServiceNow: can they place a MID Server inside the isolated REGIONAL segment specifically?

### Option 3 — Hybrid: SaaS tenant for main region, dedicated on-prem SCIM for REGIONAL *(current leaning)*
SaaS tenant (+ MID Server or direct call) for the main region; separate, self-contained on-prem SCIM deployment for the isolated REGIONAL vault, with its own service account and MID Server.
- Best fit for the facts gathered so far — REGIONAL isolation is the exception, not the norm.
- Two integration paths to build/maintain, but each scoped to what it needs — smaller blast radius per path.
- Requires ServiceNow to support two distinct SCIM client configs.
- **Open dependency:** whether ServiceNow can deploy a MID Server inside the isolated REGIONAL network. This needs to be confirmed before finalizing.

### Cross-cutting: indirection/middleware layer
Applies to any option above. A thin service sits between ServiceNow and CyberArk's SCIM server, holds the actual privileged credential, validates safe templates/naming/CMDB keys, and is the only thing ServiceNow's integration user ever talks to. This is the main lever available to narrow the "SCIM needs a highly privileged account" problem, since CyberArk offers no native scoped role for it.

### SCIM client vs. server roles (clarify with ServiceNow)
SCIM defines a **client** (initiator) and a **service provider/server** (owns the data). CyberArk is the server here; since ServiceNow initiates all onboarding/offboarding, ServiceNow must act as the **client**. ServiceNow's commonly-cited "native SCIM" is likely inbound (ServiceNow as server, for provisioning accounts into ServiceNow) — a different capability. Confirm whether ServiceNow has a **generic outbound SCIM client** that can target a third-party SCIM server (like Entra ID/Okta's app-provisioning connectors), or whether this must be custom-built via IntegrationHub/Flow Designer.

---

## 5. CMDB ↔ Safe ↔ User Relationship Model

- **Canonical key:** CMDB Application/App Service CI's `sys_id` (stable, immutable) stored as structured metadata inside the CyberArk safe — not a display name that can change.
- **Safe metadata fields:** CMDB App ID, ServiceNow reference/URL, Saviynt role/campaign reference, business owner, environment.
- **Reverse link:** ServiceNow CI record carries the CyberArk safe name(s) it owns, for bidirectional audit traceability.
- **SCIM group naming:** encodes app + entitlement, e.g. `PAM-<CMDBAppID>-RO` / `PAM-<CMDBAppID>-RW`, each mapped to a `ContainerPermission` on the corresponding safe(s). Group membership is the single control point — onboarding only changes group membership, never touches the safe directly.
- **Safe creation trigger:** fired from CMDB application registration (approved App ID + confirmed owner), never from a user-onboarding flow. Keep the two automations separate.
- **CMDB granularity (open question):** does a safe map at Application, Application Service, or Application Instance level (e.g., per environment/region)? Needs a joint decision with ServiceNow — affects safe-per-app granularity and how REGIONAL-hosted apps get tagged to route to the correct vault.
- **Reconciliation:** periodic job comparing CyberArk safes/permissions against CMDB + access-request records to catch orphaned safes, decommissioned-app safes, and access without valid group membership. Feed into Saviynt access certification.
- **Decommissioning:** requires human sign-off even when triggered by CMDB retirement — no auto-delete via SCIM given the blast radius.

---

## 6. Identity Information ServiceNow Needs

**Core identity attributes (per user)**
- Stable external ID (HR/employee ID or AD objectGUID) — not username, to avoid duplicate/orphaned identities on rename/rehire.
- `userName` — login/principal matching CyberArk's LDAP integration (UPN or sAMAccountName).
- Given name / family name / display name.
- Primary work email.
- Active/employment status (active, inactive, terminated, on leave).
- Employee type (employee, contractor, vendor) — may affect whether privileged access is permitted or needs extra approval.
- Manager reference — needed for approval-chain resolution.

**Directory/vault correlation attributes**
- AD/LDAP Distinguished Name or OU — must fall within CyberArk's allow-listed scope, and lets CyberArk correlate to its own LDAP-synced Vault user rather than creating a duplicate.
- Domain — relevant if multiple AD forests feed the vault.

*Open question: does CyberArk already sync users from AD/LDAP natively, separate from SCIM? If so, SCIM's role may be limited to entitlement (group/permission) management rather than full user object creation.*

**Entitlement/request attributes**
- Requested application identifier (CMDB App/App Service `sys_id`), resolvable to a CyberArk safe group.
- Requested permission tier (read-only vs. read/write), mapped to the corresponding SCIM group.
- Approval reference — ServiceNow RITM/ticket number and approver identity, for audit correlation.
- Access start/end date, if time-bound.

**Employment lifecycle attributes**
- Termination/last-working-day date — drives offboarding trigger.
- Transfer/role-change date — a "mover" event requires removing old entitlements and adding new ones, not just adding.
- Rehire handling — whether the stable external ID is reused.

**Routing/region attributes**
- Region/location indicator tied to the target application — determines routing to the main SCIM path vs. the isolated REGIONAL path.

**Audit/traceability attributes**
- Correlation ID linking the ServiceNow request to the CyberArk SCIM transaction.
- CMDB App CI `sys_id` persisted alongside the request, matching what's stored in the safe metadata (the reconciliation join key).

*Note: approval reference and correlation ID aren't standard SCIM User/Group attributes — they'd need to travel as custom/extension attributes on the payload, or be logged out-of-band and joined later. Confirm approach with ServiceNow.*

---

## 7. Questions — Internal CyberArk Team

**Architecture**
- Do we host SCIM via the CyberArk Identity SaaS tenant pointed at self-hosted PAM, or a fully on-prem SCIM server? (Note: one SCIM config can't target Privilege Cloud and self-hosted PAM simultaneously.)
- For the isolated REGIONAL vault: separate on-prem SCIM server, or can the CyberArk Identity Connector bridge it to the SaaS tenant despite isolation? Needs vendor/PS input.
- Does our current PAM version/license support the SCIM PAM extension endpoints (Containers, ContainerPermissions, PrivilegedData)?
- What are our inbound firewall/reverse-proxy/WAF requirements if ServiceNow calls us directly vs. via a MID Server?

**Privilege & scope**
- Can the SCIM service account's Vault Management right be constrained by Location/Safe hierarchy in our version, or is it tenant-wide? Needs testing/confirmation with CyberArk support.
- One shared SCIM service account, or split accounts — one for group/user membership changes, one (more tightly gated) for safe creation?
- Do we build an indirection/"safe factory" API between ServiceNow and the SCIM server to enforce template/naming/CMDB-key validation? Who owns building/running it?
- Who owns the SCIM service account's own lifecycle (creation, rotation, recertification), and does it live inside a PAM safe itself?

**Templates & governance**
- Finalize the safe-type + permission-set templates exposed to ServiceNow's catalog, and who can add/change a template later.
- Define the LDAP/AD branches and Vault groups in scope before onboarding ServiceNow — what's explicitly out of bounds.

**CMDB mapping & resilience**
- Is CyberArk's safe metadata the sole source of truth for CMDB-to-safe mapping, or do we also keep an independent internal mapping/reporting store?
- Who runs the periodic reconciliation job, and where do findings go?
- What's the break-glass process for emergency access outside the SCIM flow, and how is it reconciled back into CMDB?

**Operational**
- Expected transaction volume (onboarding/offboarding events per day) to size the SCIM server and any middleware.
- Offboarding behavior: remove SCIM group membership only, or also force session termination/credential rotation — real-time or batch?
- Audit log destination (SIEM) and retention requirements.

---

## 8. Questions — ServiceNow Team

**MID Server vs. SaaS**
- Is your instance fully SaaS, or do you already run a MID Server that could reach our internal network, including the isolated REGIONAL segment specifically?
- If MID Server-based, is connectivity outbound-only from the MID Server? Can a MID Server be deployed inside REGIONAL as its own path, separate from a global one?
- Is your SCIM support inbound only (ServiceNow as service provider), or do you also have an outbound SCIM client capability that can target a third-party SCIM server like CyberArk's? If not, will this be built as a custom IntegrationHub/Flow Designer integration?
- Should we expose our SCIM endpoint publicly (WAF-fronted), or can everything route through your MID Server into our network?
- What authentication do you support — OAuth2 client credentials, mutual TLS, both?

**Identity, approvals & auto-provisioning**
- What identity/HR source of truth do you use for requester identity, employment status, and manager/approver chain?
- Do you have an existing approval workflow engine (manager + safe-owner + security sign-off), or would this need to be built specifically for PAM access requests?
- Under what conditions, if any, would auto-provisioning/birthright access be appropriate for privileged safe access, versus always requiring human approval?
- How do you detect and signal offboarding/role-change events — real-time or batch — and what's the expected SLA to revoke access after termination?
- Who is approver of record for read vs. read/write permission — the CMDB app record's owner, or a separate access-catalog config?

**CMDB structure & safe mapping**
- Should a safe map at the Application level, Application Service level, or down to Application Instance (e.g., per environment/region)?
- If instance-level, how do you tag environment and region in the CI (relevant to REGIONAL vault routing)?
- Who owns creating/maintaining the Application (or App Service) CI that triggers safe creation, and what's its change-approval process?
- Will ServiceNow retain the authoritative CMDB-to-safe mapping, or should ServiceNow query CyberArk at request time to resolve which safe(s) an application maps to?
- When a user requests access to an application, how does ServiceNow resolve the target safe(s) — live SCIM lookup, or a cached mapping?
- Is there a stable, immutable CI identifier (`sys_id`/correlation ID) we can persist as safe metadata, rather than a display name?
- What's your process if the mapping drifts (safe renamed, app retired) — any CMDB health-check we should hook our reconciliation into?

**Data residency**
- Is REGIONAL-related CMDB/access-request data hosted in an REGIONAL data center, or elsewhere?
- Are there residency/sovereignty rules constraining where REGIONAL PAM-related data can be stored, processed, or transited — including via a MID Server or middleware?
- Does compliance require the REGIONAL integration path to stay entirely within-region, ruling out a shared global MID Server or Identity tenant for that segment?

**Operational**
- What logging/audit trail do you provide for provisioning actions, and can we correlate your request IDs with our CyberArk audit trail?
- What's your rollback/retry behavior if a request partially fails (e.g., safe created but group sync fails)?
- Who's the ServiceNow-side owner/support contact post go-live?

---

## 9. Open Decisions / Next Steps

- [ ] Confirm with CyberArk (vendor/PS) whether Vault Management can be scoped by Location, and whether the isolated REGIONAL vault can reach the SaaS Identity tenant via connector.
- [ ] Confirm with ServiceNow whether they have an outbound SCIM client capability or need to build custom, and whether a MID Server can be placed inside the isolated REGIONAL network.
- [ ] Decide CMDB mapping granularity (Application vs. Application Service vs. Application Instance) jointly with ServiceNow.
- [ ] Decide single vs. split SCIM service accounts, and whether an indirection/"safe factory" layer will be built — and who owns it.
- [ ] Confirm REGIONAL data residency constraints before finalizing Option 1 vs. Option 3 architecture.
- [ ] Define safe/template catalog and SCIM group naming convention with CyberArk and ServiceNow both represented.
