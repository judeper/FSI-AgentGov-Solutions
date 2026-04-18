# Changelog

All notable changes to Agent Registry Automation are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

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

*Agent Registry Automation v1.0.2 — FSI Agent Governance Framework*
