CyberArk WPM Support and Escalation Runbook
Item	Value
Service	CyberArk Workforce Password Management (WPM), SaaS tenant
Tenant name / ID	[TENANT NAME OR ID]
Document owner	[NAME AND TEAM]
Audience	Service desk, L2 support, engineering, security operations
Last reviewed	[DATE]
Next review due	[DATE, NO MORE THAN SIX MONTHS AFTER LAST REVIEW]
1. Purpose and scope

WPM runs as a CyberArk-hosted SaaS tenant. CyberArk makes the platform and tenant configuration changes that we cannot make ourselves, so most of our work is deciding which side of that line an issue sits on, collecting the right evidence and raising the right request at the right priority.

This runbook covers support issues, incidents and change requests for the WPM tenant. It does not cover the PAM vault or credential rotation, which are outside the current WPM deployment scope. Secure Web Sessions is not part of the deployment.

2. Responsibility split

Complete this table from the contract, the support entitlement and the permissions visible in the tenant admin portal. Anything we cannot change ourselves defaults to CyberArk.

Area	Our team	CyberArk	Notes
Tenant provisioning and platform configuration	Request and approve	Implement	[CONFIRM WHICH SETTINGS ARE SELF-SERVICE]
Service availability, patching and upgrades	Monitor and report impact	Own	Check the status page first
Identity provider and SSO configuration	Own	Advise on tenant-side settings	[IDP NAME]
User and group provisioning	Own	Advise on tenant-side faults	[PROVISIONING METHOD]
Browser extension rollout and versions	Own	Publish releases and advise on compatibility	[DEPLOYMENT TOOL]
Endpoint, browser and network issues	Own	None	Includes proxy and TLS inspection
End user support and training	Own	None	
Licence and entitlement changes	Approve and request	Implement	Via account team
Security incident involving tenant data	Lead the response	Support and provide logs	See section 9
Product defects and feature requests	Raise and track	Fix or assess	
3. Triage

Work through these questions in order before escalating.

How many users are affected? One user points to the endpoint, the browser or the account. Many users point to a shared dependency such as SSO, the extension release or the platform.
Is CyberArk reporting an incident? Check [CYBERARK STATUS PAGE URL] and any notification emails sent to [SHARED MAILBOX]. If an incident is open, link our ticket to it and do not raise a duplicate case unless our impact differs.
Is it on our side? Check the identity provider, SSO assertions, provisioning, recent browser or extension updates, proxy or firewall changes and endpoint security software.
Can it be reproduced? Try a second user, a second browser and a second network. Record the result of each.
Has anything changed recently? Check our change calendar and CyberArk release notices for the last 14 days.
Evidence to collect before any escalation
Affected users or groups and how many
Exact timestamps with timezone for first occurrence and latest occurrence
Browser name and version, extension version and operating system
Screenshots and the exact error text
Correlation IDs, request IDs or error codes shown by the extension or the tenant
Results of the reproduction tests above
What has already been tried and the outcome
4. When to raise a case with CyberArk
Raise a case when
The status page or our own testing shows a platform outage or degradation affecting the tenant
The fault survives our own checks in section 3 and the evidence points to the platform
A configuration change is needed that only CyberArk can make
There is suspected data exposure, unauthorised access or other security impact on the tenant
A licence, entitlement or tenant setting change is needed
A confirmed product defect needs a fix or a workaround
A feature gap blocks a business requirement (raise as an enhancement request, not an incident)
Fix locally and do not escalate when
A single user has a browser, profile or endpoint fault that a clean profile or reinstall fixes
SSO or provisioning faults trace to our identity provider or our group changes
The cause is a proxy, firewall or TLS inspection change on our network
A user has forgotten their own credentials and a documented self-service or reset route exists
The question is a how-to that existing documentation answers
5. Severity mapping

Take CyberArk's severity definitions and response targets from the support entitlement and enter them below. Do not use the placeholders as final values.

Our priority	Business impact	CyberArk severity	CyberArk response target	Contact method
P1 Critical	Service unavailable for all or most users, or confirmed security impact	[SEVERITY]	[TARGET]	Case plus phone call
P2 High	Major function degraded or a large group affected, no workaround	[SEVERITY]	[TARGET]	Case, phone if no response in target
P3 Medium	Limited users affected or a workaround exists	[SEVERITY]	[TARGET]	Case
P4 Low	Question, minor defect or enhancement request	[SEVERITY]	[TARGET]	Case

Who can declare P1: [ROLES, FOR EXAMPLE INCIDENT MANAGER OR ON-CALL ENGINEERING LEAD]

6. Contacts and access
Item	Detail
CyberArk support portal	[URL]
CyberArk support phone numbers	[NUMBERS BY REGION]
Support entitlement or contract reference	[REFERENCE]
CyberArk account manager	[NAME, EMAIL]
Customer success manager	[NAME, EMAIL]
Technical account manager	[NAME, EMAIL]
Tenant URL	[URL]
CyberArk status page	[URL]
Internal shared mailbox for vendor notices	[MAILBOX]
Authorised case raisers

CyberArk limits who can open and update support cases. Keep this list current and test each person's portal access when they are added.

Name	Role	Portal access tested	Date
[NAME]	[ROLE]	[YES/NO]	[DATE]
Internal escalation contacts
Level	Team	Contact	Hours
L1	Service desk	[CONTACT]	[HOURS]
L2	Application support	[CONTACT]	[HOURS]
L3	Engineering	[CONTACT]	[HOURS]
Security	Security operations	[CONTACT]	[HOURS]
Management	Incident manager on call	[CONTACT]	[HOURS]
7. Change requests to CyberArk

Any change that CyberArk implements on our tenant follows this path.

Raise internally. Create a change record describing the requested setting, the reason, the users affected and the expected result.
Approve internally. Approval from [CHANGE APPROVER ROLE] and, where it touches access or encryption settings, from security.
Submit to CyberArk. Open a case with the change record reference, the exact configuration requested, the requested date and any maintenance window constraints.
Agree timing. Confirm CyberArk's lead time of [LEAD TIME] and the implementation window with the account contact.
Validate. After implementation, test with a named pilot group using the checks defined in the change record. Record the results.
Close. Update the change record, close the CyberArk case and note any follow-up.
Back out. If validation fails, ask CyberArk to revert using the previous configuration recorded in the change record. Record the previous values before every change.

Emergency changes follow the same steps with approval from the incident manager and a retrospective change record within [NUMBER] working days.

8. Case template

Use this text for every case so that CyberArk receives the same information each time.

Title: [WPM] [short description] - [tenant name]

Severity requested: [P1-P4 per section 5]
Tenant: [name or ID]
Reported by: [name, contact details]

Summary
[Two or three sentences on what is happening and the business impact.]

Impact
Users affected: [number and groups]
Business function affected: [description]
Workaround available: [yes/no, details]

Timeline
First occurrence: [date, time, timezone]
Latest occurrence: [date, time, timezone]
Related changes or events: [list]

Technical detail
Browser and version: [value]
Extension version: [value]
Operating system: [value]
Error text or codes: [value]
Correlation or request IDs: [value]
Attachments: [screenshots, logs, HAR files]

Checks already completed
[List of checks from section 3 and results.]

Requested outcome
[Fix, workaround, configuration change or information.]

Internal references
Incident or change record: [number]
9. Major incident and communications

A major incident is any P1 or any P2 that is not resolved within [TIME].

The service desk or L2 declares the incident and notifies the incident manager.
The incident manager appoints a technical lead and a communications lead.
The technical lead raises the CyberArk case, phones CyberArk support and records the case number in the incident record.
The communications lead sends updates to stakeholders every [INTERVAL] and at each state change, using the channels listed in [COMMUNICATIONS PLAN REFERENCE].
If there is suspected data exposure or unauthorised access, security operations takes control of the incident and applies the security incident procedure. CyberArk is asked for relevant tenant logs through the open case.
If the incident affects a service in scope of DORA, the incident manager decides on regulatory reporting using [DORA INCIDENT CLASSIFICATION PROCEDURE REFERENCE]. CyberArk is a third-party ICT provider, so keep the case timeline and CyberArk's communications as evidence.
After resolution, hold a review within [NUMBER] working days. Record the cause, CyberArk's root cause statement when provided and any change needed to this runbook.
10. Fallback when WPM is unavailable

Users need access to credentials stored in WPM during an outage. Define the approved fallback here.

Scenario	Fallback	Approver	Notes
Short outage affecting login or autofill	[APPROVED WORKAROUND, FOR EXAMPLE EXPORTED EMERGENCY ACCESS PROCEDURE]	[ROLE]	[LIMITS]
Extended outage	[APPROVED WORKAROUND]	[ROLE]	[LIMITS]
Critical shared credentials	[APPROVED WORKAROUND]	[ROLE]	[LIMITS]

Record every use of a fallback in the incident record and rotate or review any credentials handled outside WPM once service resumes.

11. Known issues
Reference	Description	Workaround	CyberArk case	Status	Date added
[ID]	[DESCRIPTION]	[WORKAROUND]	[CASE NUMBER]	[OPEN/FIXED]	[DATE]
12. Upkeep and testing
Owner: [NAME] keeps this runbook current.
Review cycle: every six months and after every major incident.
Contact check: confirm all contacts, case raisers and portal access each quarter.
Dry run: once a year, run a table-top exercise through triage, case raising and incident communications, then record the result.
Release notices: the owner reads CyberArk release and maintenance notices as they arrive and updates sections 2, 3 and 11 where they change our support position.
Appendix: quick reference

Before escalating: check the CyberArk status page, test with a second user and browser, check SSO and provisioning on our side and gather the evidence list in section 3.

Raise with CyberArk when: the platform is down or degraded, the fault survives our checks, a change needs CyberArk to implement it, security is affected or a defect needs fixing.

Fix locally when: one user is affected and a clean profile fixes it, the cause is our SSO, provisioning, proxy or endpoint or documentation answers the question.

P1 means: phone CyberArk as well as raising the case, declare a major incident and follow section 9.

Who can raise cases: only the authorised case raisers in section 6. If none are available, contact the incident manager.

Always include: tenant, timestamps with timezone, affected user count, versions, error text, correlation IDs and what has been tried.
