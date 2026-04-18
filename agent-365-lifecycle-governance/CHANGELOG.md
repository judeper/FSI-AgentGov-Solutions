# Changelog

All notable changes to the Agent 365 Lifecycle Governance solution.

## [1.1.3] - 2026-04-16

### Fixed

#### Code bugs
- **Deploy-LifecycleGovernance-Baseline.ps1 / Test-LifecycleCompliance.ps1: Az.Accounts 5.x SecureString token bug** — `Get-AzAccessToken` returns `.Token` as a `SecureString` by default in Az.Accounts ≥ 5.0, which produced literal `"Bearer System.Security.SecureString"` headers and 401s. Added `-AsSecureString:$false` (when supported) and a SecureString-to-string fallback for forward compatibility.
- **Test-LifecycleCompliance.ps1: Dataverse URL normalization** — Trailing slash on the Dataverse OAuth audience is required, but the URL is concatenated into `"$url/api/data/..."` paths. Normalized to `$dvBase = TrimEnd('/')` for the path and `$dvResource = "$dvBase/"` for the token request.
- **Deploy-LifecycleGovernance-Baseline.ps1 / Test-LifecycleCompliance.ps1: missing pagination** — Graph `/beta/agentRegistry/agents` returns ≤100/page; previous code silently truncated. Added `do { … } while (@odata.nextLink)` loop.
- **Deploy-LifecycleGovernance-Baseline.ps1: `DataverseEnvironmentUrl` is unused** — Dropped the `Mandatory` flag so admins are not forced to supply a value the script never consumes; documented as reserved for future schema validation.
- **create_alg_dataverse_schema.py: alternate keys never deployed** — `ALTERNATE_KEYS` was defined but `create_schema()` never called a key-creation step, so the `(fsi_agentid + fsi_environmentid)` composite key was missing — every flow upsert (`PATCH …(fsi_agentid='…',fsi_environmentid='…')` with `If-Match: *`) returned `404 KeyAttributesDoesNotExist`. Added `create_alternate_keys()` that POSTs each key to `EntityDefinitions(LogicalName='…')/Keys` and called it from `create_schema()`.
- **create_alg_dataverse_schema.py: lookup nav-prop name collisions** — All three one-to-many relationships used the same `Lookup.SchemaName` (`fsi_AgentLifecycleRecordLookup`) without an explicit `ReferencingEntityNavigationPropertyName`, so Dataverse auto-disambiguated, which broke the `fsi_AgentLifecycleRecordLookup@odata.bind` references in flow docs. Added explicit `ReferencingEntityNavigationPropertyName` to each lookup.

#### Schema and documentation drift
- **flow-configuration.md: wrong event-type integers** — Several compliance events used wrong option-set values (`100000013 Zone Assigned` for Feature Flag Skip; `100000008 Deactivation Requested` for Duplicate Request Skipped; `100000009 Deactivation Approved` for Deletion Hold Extended; `100000004 Access Review Completed` for the deny path). Corrected to the dedicated values: `100000015 Feature Flag Skip`, `100000017 Duplicate Request Skipped`, `100000018 Deletion Hold Extended`, `100000019 Access Review Denied`.
- **flow-configuration.md: zone resolution** — Step 3d compared `fsi_governancezone` (which is the ELM-owned `fsi_acv_zone` option set returning `100000000`/`100000001`/`100000002`) against `1`/`2`/`3`, so every agent silently fell through to the Zone 3 branch and the upsert wrote an invalid integer to `fsi_ALG_governancezone`. Rewrote to compute `zoneOption` (raw integer) and `zone = sub(zoneOption, 100000000)` for local branching, and write `zoneOption` back to Dataverse.
- **flow-configuration.md: bad OData lookup filter** — `_fsi_agentlifecyclerecordlookup_value eq '@{var}'` quoted a GUID column. Removed the quotes (Edm.Guid).
- **flow-configuration.md: env var schema names** — Added prominent note that all env-var references in this document use the display name; the Power Automate "Get environment variable" action expects the schema name (`fsi_ALG_*`).
- **flow-configuration.md: Environment Variables Reference table** — Added missing rows (`fsi_ALG_GovernanceTeamEmail`, `fsi_ALG_SponsorMoverWorkflowId`, `fsi_ALG_SponsorLeaverWorkflowId`); removed three doc-only variables that the env-vars script does not deploy (`AgentRegistryApiVersion`, `DeletionHoldDaysDefault`, `DeletionHoldDaysZone3`) and noted them as future configurability work.
- **flow-configuration.md: PPAC API version** — Standardized to `2022-03-01-preview` to match `troubleshooting.md` and the delivery checklist (was `2021-04-01`).
- **flow-configuration.md: managed-solution wrapper version** — Bumped from `1.1.0.0` to `1.1.3.0` to match the actual package version.
- **flow-configuration.md: alternate-key prereq note** — Added explicit note that the composite alternate key must be deployed before the upsert PATCH can succeed.

#### Templates
- **templates/lifecycle-config.sample.json: wrong key shape** — Keys used display names (no prefix, e.g. `IsAgent365LifecycleEnabled`, `InactivityThreshold_Zone1` with underscore) while the env-vars script creates `fsi_ALG_*` schema names without underscores. Renamed every key to match the schema names exactly so admins copying the file get the right names.
- **templates/lifecycle-config.sample.json: contoso.com** → **example.com** per RFC 2606.
- **templates/sponsor-assignment-card.json**: added `$schema`; bumped Adaptive Card version from `1.2` to `1.4` (Teams supported).

#### Connection references
- **scripts/create_alg_connection_references.py: wrong PPAC connector ID** — Display name said "Power Platform for Admins" but the connector ID was `shared_powerappsforadmins` (the V1 Power Apps for Admins connector). The flow doc and troubleshooting both target the V2 connector. Updated to `shared_powerplatformforadmins` ("Power Platform for Admins V2").

#### Regulatory accuracy
- **README.md: Regulatory Alignment table** — Tightened every claim:
  - OCC 2011-12 / SR 11-7: Conditioned on the agent being in the firm's model inventory; firms determine which agents qualify as models.
  - FINRA 3110: Replaced "supervisory procedures for all systems" with "reasonably designed supervisory system"; replaced "helps maintain active supervisors for every agent" with "supports firm-defined supervisory procedures, ownership accountability, and review evidence."
  - FINRA 4511: Removed "supports 7-year LTR" claim; clarified that the append-only log captures lifecycle events and firms should validate SEC 17a-4 storage/format requirements.
  - SEC 17a-3/4: Removed blanket "7-year retention" claim; noted that retention varies by record category (typically 3-year communications, 6-year books and records).
- **README.md: review-cadence wording** — "aligned to regulatory requirements" → "aligned to zone policy, firm risk assessment, and written supervisory procedures."
- **README.md: deletion holds** — "Mandatory deletion hold periods" → "Configurable deletion hold periods."
- **README.md: immutable compliance event log** — Reframed as "evidence" with caveat that firms should map to FINRA 4511 / SEC 17a-4 schedules and add a SEC 17a-4-compliant archive where required.

#### Branding / placeholders
- **README.md: Microsoft product naming** — "Entra Agent 365" → "Microsoft Agent 365 / Entra Agent ID"; "Agent 365 Admin Center" → "Microsoft 365 admin center (where Agent 365 surfaces appear)"; "Entra Agent Registry" → "Microsoft Agent 365 / Entra agent registry API"; architecture diagram updated.
- **README.md / docs/troubleshooting.md: contoso.com** → **example.com** per RFC 2606.

#### Prerequisites
- **docs/prerequisites.md: Microsoft Graph permissions** — Replaced the legacy `IdentityGovernance.ReadWrite.All` blanket scope with the more specific `AccessReview.ReadWrite.All` and `LifecycleWorkflows.ReadWrite.All` per current Microsoft Graph guidance.
- **docs/prerequisites.md: Lifecycle Workflows applicability** — Added prominent note that Entra ID Governance lifecycle workflows operate against **user** principals (sponsor users), not service principals or agent identities. Reworded the two example workflows to scope by sponsor users.
- **docs/prerequisites.md: Conditional Access for Zone 3** — Rewrote as a **workload identity** Conditional Access policy: noted that group assignment is not enforced for service principals, that the Workload Identities Premium add-on license is required, and that device-compliance and sign-in-frequency controls do not apply to service-principal sign-ins.
- **docs/prerequisites.md: Long-Term Retention claim** — Removed "Required for 7-year SEC 17a-3/4 compliance"; reframed as "Recommended; configure per the firm's record schedule" with a SEC 17a-4 compliant-archive caveat.

#### Power BI / Canvas app
- **docs/power-bi-dashboard.md: DAX option-set comparisons** — DAX measures compared choice columns to text labels (`"Completed"`, `"Active"`, `"Inactive"`, `"Zone 3"`); the labels in the schema include parenthesized descriptions and would never match. Switched comparisons to integer values with explanatory comment listing the option-set integer table. Updated RLS DAX example accordingly.
- **docs/canvas-app-guide.md: Access Review Status dropdown** — Removed "Pending" and "Escalated" (which exist only on `fsi_ALG_reviewstatus` for the access-review table); kept "Not Started / In Progress / Completed / Overdue" matching `fsi_ALG_accessreviewstatus` on the lifecycle record. Updated the gallery filter formula to compare against the choice record (`ddZone.Selected`), not `.Value`.
- **docs/canvas-app-guide.md: governance-zone dropdown values** — Aligned to the schema labels including the parenthesized descriptions.

#### Versioning
- **Version footers** in DELIVERY-CHECKLIST.md, canvas-app-guide.md, power-bi-dashboard.md, troubleshooting.md, and README.md status header bumped to v1.1.3 (was a mix of v1.1.1 and v1.1.2).
- **Catalog files** (root README, AGENTS.md, CLAUDE.md, .github/copilot-instructions.md) bumped from v1.1.2 to v1.1.3.

### Notes

- AI Council technical-accuracy pass with 4 council members (Opus 4.7 code/schema, Goldeneye integration/deployability, GPT-5.4 regulatory accuracy, Opus 4.7 doc/code drift detective).
- Several lower-priority findings deferred for future minor releases: explicit deletion-hold environment variables (`fsi_ALG_DeletionHoldDaysDefault`/`Zone3`) and `fsi_ALG_AgentRegistryApiVersion`; tightening of `fsi_agentid`/`fsi_environmentid` MaxLength; case-insensitive existence check in `create_alg_environment_variables.py`; per-table try/except in `create_columns()`.

---

## [1.1.2] - 2026-04-08

### Fixed

- flow-configuration.md: replaced all picklist string labels with integer values matching `fsi_ALG_*` option sets (e.g., `'Active'` → `100000001`, `'In Progress'` → `100000001`)
- flow-configuration.md: replaced non-existent columns — `fsi_eventdate` → `fsi_timestamp`, `fsi_correlationid` → `fsi_relatedrecordid`, `fsi_reviewcompleteddate` → `fsi_decisiondate`, `fsi_reviewoutcome` → `fsi_certifierdecision`
- flow-configuration.md: replaced `fsi_agentid` on child tables (SponsorAssignment, AccessReview, DeactivationRequest) with `fsi_AgentLifecycleRecordLookup@odata.bind` lookup binding
- flow-configuration.md: moved `fsi_sponsorupn` on compliance event table into `fsi_eventdetails` JSON
- flow-configuration.md: replaced `fsi_agentname` on DeactivationRequest with `fsi_name`
- flow-configuration.md: added missing required fields — `fsi_sponsordisplayname`, `fsi_assignedby`, `fsi_AgentLifecycleRecordLookup@odata.bind` on SponsorAssignment; `fsi_name`, `fsi_triggeredby`, `fsi_timestamp` on LifecycleComplianceEvent; `fsi_name`, `fsi_zonecadence`, `fsi_AgentLifecycleRecordLookup@odata.bind` on AccessReview; `fsi_name`, `fsi_AgentLifecycleRecordLookup@odata.bind` on DeactivationRequest
- flow-configuration.md: corrected event type values — `"Feature Flag Skip"` → Zone Assigned with detail in fsi_eventdetails, `"Access Review Created"` → Access Review Started, `"Access Review Denied"` → Access Review Completed with certifier decision, `"Activity Data Unavailable"` → Inactivity Detected with detail, `"Duplicate Request Skipped"` → Deactivation Requested with detail, `"Agent Deactivated"` → Agent Disabled, `"Sponsor Reassigned"` → Sponsor Assigned with detail, `"Deletion Hold Extended"` → Deactivation Approved with detail
- flow-configuration.md: added `fsi_disabledate` to Flow 4 Step 5c deactivation approval update
- create_alg_dataverse_schema.py: replaced "Immutable event log" with "Append-only event log" for fsi_LifecycleComplianceEvent description
- dataverse-schema.md: replaced "Immutable event log" with "Append-only event log"
- DELIVERY-CHECKLIST.md: replaced "Immutable compliance event records" with "Append-only compliance event records (requires no-delete security roles)"
- Deploy-LifecycleGovernance-Baseline.ps1: documented `DataverseEnvironmentUrl` parameter as reserved for future Dataverse validation
- canvas-app-guide.md: corrected "Informational" to "None" in compliance impact dropdown to match fsi_ALG_complianceimpact option set
- Updated version footers in DELIVERY-CHECKLIST.md, canvas-app-guide.md, power-bi-dashboard.md, troubleshooting.md to v1.1.1

## [1.1.1] - 2026-04-15

### Fixed

- Test-LifecycleCompliance.ps1: compliance status now returns UNKNOWN when Dataverse queries fail instead of false COMPLIANT
- Test-LifecycleCompliance.ps1: InactiveAgents count now included in compliance decision logic
- README: replaced "Immutable Audit Trail" overclaim with conditional language requiring security role configuration
- README: added `--client-id` to interactive deployment examples (required by DataverseClient)
- CHANGELOG: replaced "immutable" overclaim with conditional language
- canvas-app-guide.md: corrected `fsi_assignedat` → `fsi_assignmentdate` (matches schema)
- Updated version footers in canvas-app-guide.md, power-bi-dashboard.md, troubleshooting.md to v1.1.0
- Added missing `.PARAMETER DryRun` to comment-based help in both PowerShell scripts

## [1.1.0] - 2026-03-20

### Added

- **Dataverse schema:** 5 custom tables — AgentLifecycleRecord, SponsorAssignment, AccessReview, DeactivationRequest, LifecycleComplianceEvent
- **Schema automation:** `create_alg_dataverse_schema.py` with `--output-docs` and `--dry-run` support
- **Environment variables:** 14 solution-level variables including feature flag (`IsAgent365LifecycleEnabled`)
- **Connection references:** Dataverse, Teams, Approvals, HTTP with Azure AD, Power Platform Admin connectors
- **Flow documentation:** Step-by-step build instructions for 6 Power Automate cloud flows
  - Flow 1: Enforce-SponsorAssignment-OnOnboard (hourly)
  - Flow 2: Schedule-AccessReview-ZoneBased (daily)
  - Flow 3: Detect-InactiveAgents-Daily (daily)
  - Flow 4: Execute-DeactivationWorkflow (called)
  - Flow 5: Monitor-SponsorChanges-Weekly (weekly)
  - Flow 6: Check-DeletionHold-Daily (daily)
- **PowerShell scripts:** Deploy-LifecycleGovernance-Baseline.ps1, Test-LifecycleCompliance.ps1
- **Templates:** Adaptive Card v1.2 for sponsor assignment notification, sample configuration JSON
- **Documentation:** Prerequisites, canvas app guide, Power BI dashboard guide, troubleshooting
- **Delivery checklist:** Phased pre-deployment and post-deployment validation tasks
- **Feature flag:** `IsAgent365LifecycleEnabled` gates all Agent 365 API calls until GA

### Notes

- Agent 365 GA target: May 1, 2026. Set feature flag to "false" until licensing is confirmed.
- Entra Lifecycle Workflow tasks for agents require Frontier-enabled tenant for pre-GA testing.
- Default access review decision is "Deny" — silence equals revocation in FSI regulatory contexts.
- `fsi_lifecyclecomplianceevent` table supports append-only operation when no-delete security roles are configured, with 7-year Dataverse LTR.
