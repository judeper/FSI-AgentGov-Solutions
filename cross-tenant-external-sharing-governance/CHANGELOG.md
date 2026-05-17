# Changelog

All notable changes to the Cross-Tenant External Sharing Governance solution.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.0.3] - 2026-05-17

### Fixed

- Refreshed Microsoft Learn-aligned guidance for Power Platform tenant isolation, replacing stale preview governance-path flow/checklist references with PPAC and `Get-PowerAppTenantIsolationPolicy` / `Set-PowerAppTenantIsolationPolicy` validation guidance.
- Updated Entra CTA flow guidance to evaluate Microsoft Graph v1.0 default and partner configuration shape using `usersAndGroups.accessType`, `applications.accessType`, `inboundTrust`, `automaticUserConsentSettings`, and tenant restrictions fields.
- Corrected solution version and control metadata drift (`1.7` instead of stale `3.1`), regenerated Dataverse schema documentation, and aligned Adaptive Card/event-type references with the schema script.
- Corrected Flow 6 Dataverse logical name references from `fsi_externaltenantid` to `fsi_externaltenanttenantid`.
- Marked client-secret authentication paths as legacy development fallback guidance and kept managed identity / interactive authentication as the recommended path.

## [1.0.2] - 2026-04-17

### Fixed (AI Council technical-accuracy review)

- **CRITICAL — Schema deployment broken:** `create_option_set` in `create_ctsg_dataverse_schema.py` invoked `client.create_record(entity, body)` with the wrong arity / wrong endpoint shape. Replaced with a `_build_optionset_metadata()` helper that wraps options in the proper `Microsoft.Dynamics.CRM.OptionSetMetadata` payload required by the Dataverse Web API GlobalOptionSetDefinitions endpoint.
- **CRITICAL — `fsi_ctsg_eventtype` mismatch:** The Python schema only declared 17 values but flows referenced values 17–20. Expanded to 21 values (added Feature Flag Skip=17, Flow Error=18, Duplicate Remediation Skipped=19, Critical Finding Manual Remediation Required=20). Reconciled the value list in `DELIVERY-CHECKLIST.md` to match.
- **CRITICAL — Wrong Power Platform Admin connector ID:** Connection references used `shared_powerappsforadmins` (legacy V1 admin connector). Replaced with `shared_powerplatformforadmins` (current V2). V1 actions referenced by flows do not exist in V1.
- **CRITICAL — Wrong Microsoft Graph connector:** Connection references used `shared_microsoftgraphsecurity`, which is a Microsoft Graph **Security** connector that does not expose `/policies/crossTenantAccessPolicy`, `/tenantRelationships`, or `/users` guest queries. Replaced with `shared_webcontents` (HTTP with Microsoft Entra ID) per Microsoft Learn guidance, with documentation that the post-deploy step must rebind those CRs to the actual HTTP-with-Entra connection.
- **CRITICAL — Environment-variable name drift:** Flow doc, deployment checklist, and PowerShell scripts referenced short names (`IsCrossTenantGovernanceEnabled`, `CTABaseline_InboundB2BBlocked`, `SecurityTeamUPN`, `GovernanceCommitteeUPN`, `GovernanceTeamEmail`, `FlowAdministrators`) while the actual environment variables ship with the `fsi_CTSG_` prefix. Find/replaced across `docs/flow-configuration.md`, `DELIVERY-CHECKLIST.md`, and the README Quick Start. Bumped declared count to 13.
- **CRITICAL — Missing environment variable:** Flow 2 referenced a `GovernanceTeamChannelId` that was never declared. Added `fsi_CTSG_GovernanceTeamChannelId` to `create_ctsg_environment_variables.py`.
- **CRITICAL — Required-field omissions on `fsi_externalsharefinding`:** Layer 1/2 findings have no agent context, so `fsi_AgentId`, `fsi_AgentName`, and `fsi_EnvironmentId` were marked `required=False`. Otherwise Flow 1 / 3 / 5 would fail at the Create Row action with "missing required field".
- **CRITICAL — Invalid alternate key:** `fsi_FindingDeduplicationKey` referenced a picklist column (`fsi_findingtype`) and nullable columns. Dataverse rejects picklists in alternate keys. Removed the composite key; flow-level dedup now relies on `$filter` prior to Create.

### Fixed (HIGH severity)

- **`Get-AzAccessToken` SecureString:** `Deploy-CrossTenantBaseline.ps1` did not handle the SecureString return type added in Az.Accounts 2.17+. Added `-AsSecureString` and `ConvertFrom-SecureString -AsPlainText` to mirror the Test script's pattern.
- **Wrong Power Platform admin API endpoints:** `Deploy-CrossTenantBaseline.ps1` called `https://api.powerplatform.com/governance/tenantSettings` and `.../crossTenantPolicies`, which are not real endpoints on the documented public PP admin API surface. Replaced with the BAP (Business Application Platform) admin endpoints `https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/tenantSettings` and `.../crossTenantConnectionAllowPolicy` (api-version `2020-10-01`), and updated the token resource to `https://service.powerapps.com/`. Customers must verify the deployed property names against the live response in their tenant before activating Flow 1.
- **External-domain regex bug:** Guest-UPN parsing in `Deploy-CrossTenantBaseline.ps1` line 383 used `_([^#]+)#EXT#@` which captures the wrong substring for UPNs with underscores in the local part. Anchored on the LAST underscore before `#EXT#`.
- **`Az.Accounts` version pin:** Both PowerShell scripts now `#Requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.17.0' }` so the SecureString contract is guaranteed.
- **Alternate key `@odata.type`:** Added `Microsoft.Dynamics.CRM.EntityKeyMetadata` discriminator to the alternate key creation payload.

### Fixed (MEDIUM severity & language)

- **Adaptive cards bumped 1.2 → 1.3:** Templates already used 1.3 properties (`label`, `isRequired`); declared schema version updated to match.
- **`fsi_eventdetails` filter:** Flow 6 used `$filter=fsi_eventdetails eq` against a memo column. Replaced with `fsi_externaltenantid eq` (string column).
- **`fsi_detectedby` typo:** Flow 6 step 5c used `Monitor-AnnualTenantReviews-Daily`. Corrected to the actual flow name `Send-AnnualReviewReminders-Daily`.
- **`deploy.py` table-name typo:** Post-deployment instructions referenced an "AllowedTenant table" that does not exist. Corrected to `fsi_approvedexternaltenant`.
- **`approved-tenant-sample.json`:** `relationshiptype` corrected to `0` (Subsidiary) to match the justification text. Replaced `contoso.com` / "Contoso" with `example.com` / "Example" per RFC 2606.
- **Regulatory citation accuracy (README Regulatory Alignment table):**
  - SEC 17a-4 immutability claim softened: clarified that Dataverse LTR provides retention; SEC 17a-4 WORM/non-rewriteable storage characteristics must be validated with counsel.
  - OCC 2011-12 / Fed SR 11-7 clarified as model-risk guidance (not third-party risk).
  - SOX 302/404 narrowed to ICFR scope.
  - FINRA 4370 (BCP) and FINRA 3110 (supervision) split into separate rows with distinct claims.
  - NYDFS narrowed to Section 500.11 (third-party service provider security policy).
- **Control mapping:** Replaced link to non-existent Control 3.1 with Control 1.7 (Audit Logging and Monitoring).
- **Required Entra roles section** added to `docs/prerequisites.md` — Entra Global Admin (one-time consent), Cross-Tenant Access Administrator (least-privilege CTA), Power Platform Admin (PPAC), Privileged Role Administrator (MI app role grants).
- **README Quick Start** now includes `--tenant-id` and `--environment-url` arguments (previously incomplete) and uses the full `fsi_CTSG_*` env-var name. Added a callout about adjacent controls (Tenant Restrictions v2, SharePoint external sharing, OneDrive sharing, Conditional Access for guests).
- **README "all three layers" wording** softened to "validates all three layers together along with adjacent controls" to avoid implying any single solution provides full coverage.
- **`requirements.txt`:** Added `requests>=2.31.0` (used implicitly via the shared Dataverse client).

## [1.0.1] - 2026-04-15

### Fixed

- Critical: CTA compliance validation now queries correct column fsi_unapprovedpartnercount (was fsi_unapprovedcount, which belongs to the isolation table)

## [1.0.0] - 2026-03-20

### Added

- **Three-layer governance model** — Power Platform Tenant Isolation (Layer 1), Entra Cross-Tenant Access (Layer 2), Copilot Studio Agent Shares (Layer 3)
- **Dataverse schema** — 5 tables:
  - `fsi_approvedexternaltenant` — Authoritative external tenant allow list
  - `fsi_externalsharefinding` — External sharing violations per agent
  - `fsi_tenantisolationrecord` — Daily tenant isolation audit snapshots
  - `fsi_entractarecord` — Weekly Entra CTA audit snapshots
  - `fsi_crosstenantcomplianceevent` — Immutable compliance event log (7-year LTR)
- **Python deployment scripts** — `create_ctsg_dataverse_schema.py`, `create_ctsg_environment_variables.py`, `create_ctsg_connection_references.py`, `deploy.py`
- **PowerShell governance scripts** — `Deploy-CrossTenantBaseline.ps1`, `Test-CrossTenantCompliance.ps1`
- **Power Automate flows (documentation-only, manual build):**
  - Flow 1: Validate-TenantIsolation-Daily
  - Flow 2: Detect-ExternalAgentShares-Daily (5-value guest detection method)
  - Flow 3: Audit-EntraCrossTenantSettings-Weekly
  - Flow 4: Execute-ExternalTenantOnboarding (dual-approval with Expired timeout)
  - Flow 5: Remediate-UnauthorizedExternalAccess (approval-gated)
  - Flow 6: Send-AnnualReviewReminders-Daily (90/30/overdue thresholds)
- **Two Managed Identities** — MI-CrossTenantReadOnly (Flows 1-3, 6), MI-CrossTenantReadWrite (Flows 4-5)
- **12 environment variables** including feature flag and CTA baseline configuration
- **Controls:** 1.1, 1.18, 2.1, 2.8, 3.1, 1.11
- **Regulatory alignment:** GLBA 501(b), OCC 2011-12, SOX 302/404, FINRA 4370/3110, NYDFS 23 NYCRR 500, FFIEC
