# Changelog

All notable changes to Agent Registry Automation are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Fixed

- **Major (discovery API correction):** Replaced the unverified Power Platform "Bots API" discovery surface with authoritative Microsoft APIs. Environment enumeration now uses the documented BAP admin API (`https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2020-10-01`, audience `https://service.powerapps.com/`), and agent enumeration reads each environment's Dataverse `bot` table (entity set `bots`, PK `botid`, name `name`). The prior `https://api.powerplatform.com/appmanagement/environments/{id}/bots?api-version=2022-03-01-preview` route is undocumented and conflicts with the AppManagement namespace (which is scoped to Microsoft-provided application packages, per the Power Platform REST API reference). Affects `scripts/Deploy-AgentRegistry-Baseline.ps1` and `docs/flow-configuration.md` (Flow 1). The `2.0.0` change that swapped `/powervirtualagents/.../bots` for `/appmanagement/.../bots` was itself unverified.
- **Major:** Removed the `properties.botFrameworkEndpoint` → `fsi_agentendpointurl` mapping. The Dataverse `bot` table has no Bot Framework endpoint column ([bot table reference](https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot)); `fsi_agentendpointurl` is left blank during discovery.
- **Major (auth audiences):** Baseline script now requests a BAP token (audience `https://service.powerapps.com/`) for environment enumeration and a per-environment Dataverse token (audience = each environment's `instanceUrl` from `properties.linkedEnvironmentMetadata`) for `bot`-table reads, instead of a single `https://api.powerplatform.com` token.
- **Major:** Corrected prerequisite permissions — removed the non-existent `Bot.Read.All` / `Environment.Read.All` Power Platform API application permissions. Environment enumeration is authorized by the Power Platform Admin role; agent discovery requires a Dataverse security role with `bot`-table read in each scanned environment. `docs/prerequisites.md`, `docs/troubleshooting.md`.
- **Minor:** Updated network endpoint list (`api.bap.microsoft.com` replaces `api.powerplatform.com`), connection-reference descriptions, README architecture diagram, Known Limitations, and Platform Update Notes to match the corrected discovery mechanism.
- **Minor:** Reworded the README Agent Store future-enhancement bullet ("add an `fsi_agentsource` choice column" instead of "extending" a non-existent choice set).

### Notes

- Verified against Microsoft Learn (June 2026): Power Platform REST API reference, BAP "List environments", Dataverse `bot` table reference, and Power Platform programmability authentication. See `LAB-VALIDATION.md` for the full evidence report and runtime-only caveats.
- Version header and manifest bump deferred to maintainer: these corrections warrant a minor version bump (suggest `2.2.0`) plus the standard 4-file catalog sync and `manifest.yaml` update, which were intentionally left untouched in this validation pass.

---

### Fixed

- **Major**: Replaced `contoso.crm.dynamics.com` with `example.crm.dynamics.com` (RFC 2606) in `fsi_ARA_DataverseEnvironmentUrl` description. `scripts/create_environment_variables.py:108`. (council review M2)
- **Major**: Unified alternate key references to canonical schema name `fsi_AgentEnvUniqueKey` (logical: `fsi_agentenvuniquekey`). Previously `scripts/deploy.py:45` used `fsi_agent_env_uniquekey` and `docs/flow-configuration.md:234` + `docs/troubleshooting.md:86` used `fsi_ak_agentinventory_agentenv`; none matched the deployed key. (council review M3)
- **Minor**: PowerShell 5.1 compatibility — replaced `Get-Date -Format ... -AsUTC` (PS 7-only parameter) with `(Get-Date).ToUniversalTime().ToString(...)` in `Deploy-AgentRegistry-Baseline.ps1:106` and `Test-AgentRegistryCompliance.ps1:108`. (style §10 sweep)
- **Minor**: Updated `DELIVERY-CHECKLIST.md` release date from April 2026 to May 2026 to match the v2.1.x release window. (council review m5)
- **Minor**: Updated CHANGELOG footer reference from v1.0.2 to v2.1.1 to match current version. (council review m6)

### Notes

- Version-string headers across `README.md`, `DELIVERY-CHECKLIST.md`, `docs/prerequisites.md`, `docs/troubleshooting.md`, `docs/flow-configuration.md`, and `templates/agent-registry-config.sample.json` were bumped from v2.1.0 to v2.1.1.
- Council review minors deferred to a future minor bump (out of scope for this patch): M1 shared-client refactor (`ara_client.py` → `scripts/shared/dataverse_client.py`; would touch >10 files, REFINEMENT 4); m1 picklist option-set label extraction in `_col_type_label` (doc-quality only, standalone); m2/m3/m4 `fsi_ARA_IncludeSandboxEnvironments` feature gap (requires new env var + new PS parameter); m7 Flow 2 Step 6 ambiguity (doc-only clarification).

---

## [2.1.0] - 2026-05-04

### Changed

- Refreshed authentication guidance to be managed-identity/workload-identity-first, with certificate authentication as the workstation fallback and client secrets documented only as a legacy development fallback.
- Added Dataverse and Power Platform API paging support to the Python client and baseline discovery script.
- Updated Flow 1 build guidance to use schema-correct zone values and required create fields while preserving approval workflow state on rediscovery.
- Updated Flow 3 guidance for Microsoft Entra Agent ID preview terminology, feature-flagged endpoint confirmation, `fsi_entraregistrystatus`, and the modeled `EntraSynced` event value.
- Added current Power Platform, PAC CLI, and Microsoft Graph tooling validation guidance for the 2026-Q2 Microsoft Learn refresh.

---

## [2.0.0] - 2026-04-30

### BREAKING

- **`docs/dataverse-schema.md` is now generated** from `scripts/create_dataverse_schema.py` via the new `--output-docs` flag. Hand-edits to the schema doc will be overwritten — modify the schema script and regenerate. The previous hand-written schema doc described many columns that did not exist in the schema script (root cause of the v1.0.x flow drift).
- **Power Platform Bots API path** corrected from `/powervirtualagents/environments/{envId}/bots` to `/appmanagement/environments/{envId}/bots` in `Deploy-AgentRegistry-Baseline.ps1`. The `powervirtualagents` path is no longer the supported route.
- **Bot identifier source switched** from `bot.id` (an ARM resource path) to `bot.name` (the GUID) when populating `fsi_agentid`. Existing rows whose `fsi_agentid` was an ARM path will not be matched by the v2.0.0 baseline scan and will be re-created with the correct GUID. **Migration:** before upgrading, export and reconcile any rows where `fsi_agentid` starts with `/providers/`; after upgrade, delete the duplicate ARM-path rows.
- **Test-AgentRegistryCompliance.ps1 SLA check** now reads `fsi_sladeadline` from each registration request instead of using a hardcoded 72-hour threshold. This honours the per-request SLA stamped by the registration flow and supports zone- or risk-tier-specific SLAs. The `$script:SlaDeadlineHours` variable was removed.
- **`docs/flow-configuration.md` rewritten** for column accuracy. All references to non-existent columns (`fsi_isquarantined`, `fsi_quarantinedon`, `fsi_quarantinereason`, `fsi_eventsource`, `fsi_severity`, `fsi_correlationid`, `fsi_changetype`, `fsi_previousownerstatus`, `fsi_isescalated`, `fsi_orphanedon`, `fsi_approver`, `fsi_approvaloutcome`, `fsi_discoveredon`) replaced with their schema-correct equivalents (`fsi_publishedstatus`, `fsi_details`, `fsi_eventtimestamp`, `fsi_approvedby`, `fsi_approvedat`). All option-set values bumped from the placeholder `1000x` range to the canonical `100000000+` range.
- **Lookup-based agent retrieval removed** from Flow 2 (Process-RegistrationRequest). The flow now joins `fsi_registrationrequest` to `fsi_agentinventory` by business key (`fsi_agentid` + `fsi_environmentid`) instead of a lookup column that does not exist on the request table.

### Fixed

- Critical: Entity set name `fsi_agentinventorys` → `fsi_agentinventories` (default Dataverse pluralization for nouns ending in `y`) in `Deploy-AgentRegistry-Baseline.ps1`, `Test-AgentRegistryCompliance.ps1`, and `ara_client.py`.
- Critical: `Write-AgentInventoryRecord` is now idempotent. On *update*, only discovery-tracking fields (display names, endpoint URL, `fsi_lastscannedat`, `fsi_publishedstatus`, `fsi_rawjson`) are PATCHed; workflow state (`fsi_registrationstatus`, `fsi_zone`, `fsi_isorphaned`, `fsi_ownerupn`) is preserved. v1.0.x clobbered approval state on every re-scan.
- High: `fsi_publishedstatus` now defaults to `Draft` instead of being omitted when the Bots API returns no value, so the create call succeeds (the column is `ApplicationRequired`).
- High: `fsi_ownerupn` now defaults to `unknown@unassigned.local` and `fsi_isorphaned = true` when the Bots API does not return an owner, so the create call succeeds (the column is `ApplicationRequired`).
- High: `docs/troubleshooting.md` diagnostic queries corrected — replaced `fsi_isquarantined`, `fsi_occurredon`, `fsi_requeststatus`, `fsi_approvaldeadline`, `fsi_isescalated` with their canonical column names (`fsi_publishedstatus`, `fsi_eventtimestamp`, `fsi_approvalstatus`, `fsi_sladeadline`, `fsi_escalationtarget`).
- Medium: `contoso.com` → `example.com` (RFC 2606) across all docs and scripts.
- Medium: Sample config `templates/agent-registry-config.sample.json` version bumped to 2.0.0.
- Medium: Doc footers across `docs/*.md` bumped to v2.0.0.

### Added

- `scripts/create_dataverse_schema.py --output-docs PATH` — generates a Markdown reference for tables, columns, option sets, and alternate keys directly from the in-memory schema definitions. This is now the only supported way to update `docs/dataverse-schema.md`.

---

## [1.0.2] - 2026-04-16

### Fixed

- Critical: Added `fsi_name` (primary name column) to agent inventory records in Deploy-AgentRegistry-Baseline.ps1
- Critical: Added `fsi_name` to compliance event payload in Deploy-AgentRegistry-Baseline.ps1
- Critical: `fsi_publishedstatus` now maps Bots API string values to option-set integers matching the Dataverse schema
- Critical: Environment ID uses `$env.name` (GUID) instead of `$env.id` (ARM resource path) in Deploy-AgentRegistry-Baseline.ps1
- README: Quick Start examples corrected to use actual script parameters (`-DataverseUrl`)
- CHANGELOG: Fixed script filename reference (`Test-AgentRegistryCompliance.ps1`, not `Validate-AgentRegistry-Compliance.ps1`)
- Troubleshooting: Fixed environment variable count from 7 to 10
- Troubleshooting: Fixed fallback auth example to match actual script parameters
- DELIVERY-CHECKLIST: Release date corrected to April 2026

---

## [1.0.1] - 2026-04-15

### Fixed

- Critical: Zone option-set mapping corrected (Zone1=100000001, Zone2=100000002, Zone3=100000003) in both Deploy and Validate scripts
- Critical: Compliance event payload uses correct columns (fsi_details, fsi_eventtimestamp instead of fsi_eventdetails, fsi_correlationid)
- Critical: Validate script uses fsi_eventtimestamp instead of non-existent fsi_createdon
- Critical: Validate script uses fsi_approvalstatus instead of non-existent fsi_requeststatus
- README: fixed --environment flag to --environment-url in deployment examples

---

## [1.0.0] - 2026-03-15

### Added

- **Dataverse Schema** — 4 tables for agent lifecycle governance:
  - `fsi_agentinventory` — Master agent registry with alternate key on (`fsi_agentid`, `fsi_environmentid`)
  - `fsi_registrationrequest` — Registration request tracking with SLA and escalation
  - `fsi_agentcomplianceevent` — Immutable compliance event log (LTR-enabled)
  - `fsi_ownershipaudit` — Ownership change audit trail
- **Python Deployment Scripts:**
  - `create_dataverse_schema.py` — Schema deployment with option sets and alternate keys
  - `create_environment_variables.py` — 7 environment variables for flow configuration
  - `create_connection_references.py` — 4 connection references for Power Automate flows
  - `deploy.py` — Orchestrator with `--dry-run`, `--tables-only`, `--vars-only`, `--refs-only`
- **PowerShell Governance Scripts:**
  - `Deploy-AgentRegistry-Baseline.ps1` — Baseline inventory export (Managed Identity auth)
  - `Test-AgentRegistryCompliance.ps1` — Compliance validation with examiner reporting
- **Power Automate Flows** (documentation-only, manual build):
  - Flow 1: Discover-UnregisteredAgents-Daily — daily Bots API scan across all environments
  - Flow 2: Enforce-RegistrationApproval-Gate — Teams approval with SLA tracking and escalation
  - Flow 3: Sync-EntraAgentRegistry — Entra Agent Registry sync (feature-flagged, disabled by default)
  - Flow 4: Detect-OrphanedAgents-Weekly — orphan detection for departed or inactive owners
- **Documentation:**
  - Dataverse schema reference (`docs/dataverse-schema.md`)
  - Flow configuration with manual build instructions (`docs/flow-configuration.md`)
  - Prerequisites guide (`docs/prerequisites.md`)
  - Troubleshooting guide (`docs/troubleshooting.md`)
  - Delivery checklist (`DELIVERY-CHECKLIST.md`)
  - Sample configuration template (`templates/agent-registry-config.sample.json`)
- Supports Controls 1.2 (primary), 1.7, 2.1, 2.13 (secondary)

### Regulatory Alignment

- FINRA Rule 4511 — Books and records for AI agent systems
- SEC Rule 17a-3/4 — Immutable retention via Dataverse LTR
- OCC Bulletin 2011-12 — Model inventory with ownership and risk classification
- Fed SR 11-7 — Comprehensive inventory with zone-based risk classification
- GLBA 501(b) — Safeguards with owner validation and orphan detection

### Technical Decisions

- Bots API (`2022-03-01-preview`) selected for agent discovery — only available API for bot enumeration across environments
- Entra Agent Registry sync is feature-flagged off by default pending API GA
- Alternate key on (`fsi_agentid`, `fsi_environmentid`) enables upsert-based idempotent discovery
- `fsi_agentcomplianceevent` designed for Dataverse Long-Term Retention (7-year SEC 17a-3/4 support)
- Office 365 Users connector used for time zone lookup in SLA calculations; configurable fallback for DLP-restricted environments

---

*Agent Registry Automation v2.1.1 — FSI Agent Governance Framework*
