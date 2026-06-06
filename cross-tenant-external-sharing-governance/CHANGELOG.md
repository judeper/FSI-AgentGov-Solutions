# Changelog

All notable changes to the Cross-Tenant External Sharing Governance solution.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Fixed (technical accuracy review vs Microsoft Learn)

- **Fabricated Power Platform API permission scopes removed.** README, `docs/prerequisites.md`,
  `docs/troubleshooting.md`, and `DELIVERY-CHECKLIST.md` listed
  `PowerPlatform.Admin.Read.All` and `PowerPlatform.Admin.ReadWrite.All` as Microsoft
  Graph-style "Application" permissions on a "Power Platform API". No such scopes exist.
  The Power Platform admin (BAP) API this solution calls does not expose granular
  application permission scopes; a service principal or managed identity is granted
  tenant-admin-equivalent access by registering it as a Power Platform admin management
  application via `New-PowerAppManagementApp`. The Microsoft Graph scopes (Policy.Read.All,
  User.Read.All, CrossTenantInformation.ReadBasic.All, Organization.Read.All,
  Policy.ReadWrite.CrossTenantAccess) are unchanged. Added a note that the read-only vs.
  read-write separation between the two managed identities is enforced operationally, and
  that the newer `api.powerplatform.com` surface uses delegated permissions plus RBAC roles
  (Reader/Contributor) for service principals. Source:
  https://learn.microsoft.com/power-platform/admin/programmability-authentication-v2
- **Corrected the Power Platform environment-list endpoint in `docs/flow-configuration.md`.**
  Flow 2 step 8 ("Get All Power Platform Environments") used
  `/appmanagement/environments?api-version=2022-03-01-preview`. The documented GA
  listing endpoint is `/environmentmanagement/environments?api-version=2024-10-01`
  (`appmanagement/environments/{id}/operations` is the app-install operations path, not
  the environment list). Source:
  https://learn.microsoft.com/power-platform/admin/programmability-authentication-v2

### Fixed (lab-readiness validation)

- **`Scan-ManagedEnvBotSharingBaseline.ps1` used non-existent governance
  properties.** The script evaluated `extendedSettings.botSharingAccessControl`,
  `extendedSettings.botSharingSharingApproval`, and
  `extendedSettings.botSharingMaxShareLimit` — none of which exist in the Power
  Platform Managed Environments `governanceConfiguration` schema. Against a live
  tenant every environment would have been flagged non-compliant on all three
  checks because the property lookups always returned `$null`. Replaced with the
  documented agent-sharing properties from the Managed Environments "Limit
  sharing" control:
  `bot-limitSharingMode` (not `noLimit`; expected
  `ExcludeSharingToSecurityGroups`), `bot-authoringSharingDisabled` (expected
  `True`), and `bot-maxLimitUserSharing` (positive viewer limit; `-1` means
  unlimited). Also removed the invented "sharing approval workflow" check
  (Managed Environments has no such property) and repurposed it to the documented
  editor-sharing toggle. Source:
  https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits
  The `BaselinePolicy` parameter default changed from `Restricted` to the
  documented enum value `ExcludeSharingToSecurityGroups`.

## [1.1.0] - 2026-05-23 [BREAKING DEPLOY]

### Changed (BREAKING)

- **CTSG-specific option-set values migrated from 0-based to 100000000-based.**
  All 14 `fsi_ctsg_*` global option sets now use the Dataverse default integer
  encoding (100000000+) instead of the legacy 0-based encoding deployed by
  v1.0.x. Existing deployments **must** run
  `scripts/migrate_ctsg_optionsets_v1_1_0.py` after re-publishing the schema
  and **before** re-publishing the flows.

  Migration value mapping (delta = +100000000 for every legacy value):

  | Option Set | Label | v1.0.x | v1.1.0 |
  |---|---|--:|--:|
  | `fsi_ctsg_relationshiptype` | Subsidiary | 0 | 100000000 |
  | `fsi_ctsg_relationshiptype` | Partner | 1 | 100000001 |
  | `fsi_ctsg_relationshiptype` | Vendor | 2 | 100000002 |
  | `fsi_ctsg_relationshiptype` | Regulator | 3 | 100000003 |
  | `fsi_ctsg_relationshiptype` | Auditor | 4 | 100000004 |
  | `fsi_ctsg_relationshiptype` | Other | 5 | 100000005 |
  | `fsi_ctsg_approvalstatus` | Pending → Revoked | 0 → 4 | 100000000 → 100000004 |
  | `fsi_ctsg_risktier` | Low → Critical | 0 → 3 | 100000000 → 100000003 |
  | `fsi_ctsg_ppisolationdirection` | Inbound → None | 0 → 3 | 100000000 → 100000003 |
  | `fsi_ctsg_findingtype` | Unapproved Tenant Isolation Exception → Approved Tenant - Review Required | 0 → 4 | 100000000 → 100000004 |
  | `fsi_ctsg_findingstatus` | Open → False Positive | 0 → 4 | 100000000 → 100000004 |
  | `fsi_ctsg_severity` | Critical → Low | 0 → 3 | 100000000 → 100000003 |
  | `fsi_ctsg_governancelayer` | Layer 1 → Layer 3 | 0 → 2 | 100000000 → 100000002 |
  | `fsi_ctsg_remediationstatus` | Pending → Deferred | 0 → 3 | 100000000 → 100000003 |
  | `fsi_ctsg_guestdetectionmethod` | EXT# Parsing → Unresolved | 0 → 4 | 100000000 → 100000004 |
  | `fsi_ctsg_isolationcompliancestatus` | Compliant → Non-Compliant - Unapproved Entries | 0 → 2 | 100000000 → 100000002 |
  | `fsi_ctsg_ctacompliancestatus` | Compliant → Non-Compliant - Unapproved Partners | 0 → 2 | 100000000 → 100000002 |
  | `fsi_ctsg_complianceimpact` | None → Critical | 0 → 4 | 100000000 → 100000004 |
  | `fsi_ctsg_eventtype` | Tenant Isolation Validated → Critical Finding Manual Remediation Required | 0 → 20 | 100000000 → 100000020 |

  **Not migrated (intentional cross-solution exception):** the shared
  `fsi_acv_zone` option set retains 0-based values
  (Unclassified=0, Zone 1=1, Zone 2=2, Zone 3=3) because it is co-owned with
  six or more sibling solutions (ACRD, ASARD, ALG, ARA, ACV, etc.). Migrating
  it in isolation would create cross-solution inconsistency. The schema script
  `SHARED_OPTIONSETS` block documents this carve-out and references
  `style-decisions.md §9` for the allowlist.

### Migration Steps (BREAKING DEPLOY)

For environments with existing v1.0.x rows:

1. **Take a Dataverse backup** of every CTSG table (`fsi_approvedexternaltenant`,
   `fsi_externalsharefinding`, `fsi_tenantisolationrecord`,
   `fsi_entractarecord`, `fsi_crosstenantcomplianceevent`) before any other
   step. A symmetric automated rollback is **not** provided — rollback requires
   restoring from this backup.
2. **Pause all CTSG flows** (Flows 1–6) in the Power Automate portal to prevent
   new rows being created against the in-flight schema.
3. **Re-publish schema:**
   `python scripts/create_ctsg_dataverse_schema.py --tenant-id <…> --environment-url <…>`
   This updates the option-set metadata to the 100000000-based values.
4. **Re-key existing rows:**
   `python scripts/migrate_ctsg_optionsets_v1_1_0.py --tenant-id <…> --environment-url <…> --dry-run`
   first to preview, then re-run without `--dry-run` to apply.
5. **Re-publish flows** (Flows 1–6). The shipped `docs/flow-configuration.md`
   already uses post-migration integer values; if you maintain customizations,
   re-key every `fsi_ctsg_*` integer literal per the mapping table above.
6. **Sample re-key Web API calls (representative — actual re-keying is done by
   the migration script in step 4; these PATCH bodies are what the script
   sends, shown here for audit-trail / manual-fallback reference):**
   ```http
   # fsi_approvedexternaltenant — re-key picklists for one row
   PATCH /api/data/v9.2/fsi_approvedexternaltenants(<recordId>)
   Content-Type: application/json
   If-Match: *
   { "fsi_relationshiptype": 100000001,
     "fsi_approvalstatus":   100000001,
     "fsi_risktier":         100000002,
     "fsi_ppisolationdirection": 100000000 }

   # fsi_externalsharefinding — re-key picklists for one row
   PATCH /api/data/v9.2/fsi_externalsharefindings(<recordId>)
   { "fsi_findingtype":        100000002,
     "fsi_findingstatus":      100000000,
     "fsi_severity":           100000001,
     "fsi_governancelayer":    100000001,
     "fsi_remediationstatus":  100000000,
     "fsi_guestdetectionmethod": 100000003 }

   # fsi_tenantisolationrecord — re-key picklist for one row
   PATCH /api/data/v9.2/fsi_tenantisolationrecords(<recordId>)
   { "fsi_compliancestatus": 100000001 }

   # fsi_entractarecord — re-key picklist for one row
   PATCH /api/data/v9.2/fsi_entractarecords(<recordId>)
   { "fsi_compliancestatus": 100000001 }

   # fsi_crosstenantcomplianceevent — re-key picklists for one row
   PATCH /api/data/v9.2/fsi_crosstenantcomplianceevents(<recordId>)
   { "fsi_eventtype":         100000017,
     "fsi_complianceimpact":  100000003 }
   ```
   Verification query (run after migration; should return 0):
   ```sql
   -- Verify no legacy rows remain (should return 0)
   SELECT COUNT(*) FROM fsi_externalsharefinding
   WHERE fsi_findingstatus < 100000000 OR fsi_severity < 100000000;
   ```
7. **Resume CTSG flows.**

### Fixed (council review)

- **C-1 — Option-set integer encoding** (this release's primary deliverable;
  see Changed → BREAKING above).
- **M-2 — `Get-AzAccessToken` SecureString handling in `Scan-ManagedEnvBotSharingBaseline.ps1`:**
  Added `#Requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.17.0' }`
  and switched both ManagedIdentity and Interactive auth branches to
  `Get-AzAccessToken -AsSecureString` followed by
  `ConvertFrom-SecureString -AsPlainText`. Matches the pattern already used by
  `Deploy-CrossTenantBaseline.ps1` and `Test-CrossTenantCompliance.ps1`.
- **M-3 — Flow doc integer-vs-label clarification:** Every
  `docs/flow-configuration.md` reference to `fsi_eventtype`, `fsi_findingtype`,
  `fsi_findingstatus`, `fsi_severity`, `fsi_governancelayer`,
  `fsi_remediationstatus`, `fsi_approvalstatus`, `fsi_guestdetectionmethod`,
  and `fsi_ppisolationdirection` now uses an integer literal with the label
  in parentheses (e.g., `fsi_eventtype` = `100000017` (Feature Flag Skip))
  instead of bare string labels. Eliminates the ambiguity that previously made
  Power Automate flow builders insert string labels into integer picklist
  fields.
- **m-2 — Schema doc drift:** Regenerated `docs/dataverse-schema.md` via
  `create_ctsg_dataverse_schema.py --output-docs`. The doc now includes the
  previously missing `fsi_AutomaticUserConsentSettings` and `fsi_InboundTrust`
  columns on `fsi_EntraCTARecord` and reflects all 100000000-based option-set
  values.
- **m-4 — "Feature Flag Skip" integer:** Promoted to integer literal
  `100000017` in the feature-flag-gate guidance.
- **m-5 — Adaptive-card language softening:** Changed
  `templates/adaptive-card-templates.json` line 333 from "Failure to complete
  the review by the due date will result in automatic suspension." to "may
  result in suspension of access pending governance committee review." per
  FSI compliance-language guidelines.

### Deferred to a later release

- **M-1 — `fsi_acv_zone` migration:** Tracked as a cross-solution-coordinated
  change; not part of CTSG v1.1.0. The known inconsistency between schema
  scripts (0-based) and
  `cross-solution-integration/scripts/powershell/IntegrationConfig.psm1`
  (100000000-based hardcoded) is documented in
  `create_ctsg_dataverse_schema.py` SHARED_OPTIONSETS and will be resolved via
  a dedicated cross-solution PR.

### Consumers updated for the new encoding

- `docs/flow-configuration.md` — reference table at top + every Layer 1/2/3
  finding-creation block + every compliance-event log + every onboarding-flow
  status transition + every annual-review reminder.
- `docs/troubleshooting.md` — finding-status / option-set troubleshooting
  guidance.
- `docs/power-apps-configuration.md` — alert-banner `Filter()` expressions on
  `fsi_approvalstatus`.
- `DELIVERY-CHECKLIST.md` — option-set value table.
- `templates/approved-tenant-sample.json` — sample record integer values.
- `scripts/governance/Test-CrossTenantCompliance.ps1` — `.PARAMETER`
  documentation + parameter defaults for the 8 picklist-value tuning knobs.

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
