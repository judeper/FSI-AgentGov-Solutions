# Changelog

All notable changes to the **agent-intake** solution will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased] — toward v1.0.0-preview

### Added — Standard + Full path foundations

- Added reviewer-role, review-decision, routing-topology, and MRM-handoff option sets to `scripts/create_fsi_intake_dataverse_schema.py` for Standard and Full path routing.
- Extended `fsi_IntakeRequest` with quorum, routing-topology, parallel-reviewer JSON, MRM handoff, and extended-question payload fields for multi-reviewer workflows.
- Extended `fsi_IntakeReview`, `fsi_IntakeApproval`, and `fsi_IntakeAuditEvent` with reviewer-role normalization, quorum metadata, sequencing support, and path-phase checkpoints.
- Regenerated `docs/dataverse-schema.md` from the updated schema script so downstream flow and portal workstreams can consume the canonical field list.
- Expanded `templates/policy-lookup-tables.yaml` with reviewer routing, quorum, MRM handoff, parallel-routing, and path-specific denial-appeal defaults.
- Added `fsi_appealofid` and `fsi_nonmrmquorummet` to `fsi_IntakeRequest`, extended `fsi_intake_status` with `InReview` / `LiveTracking`, added the bundled `fsi_intake_auditeventtype` inventory values used by the 12 documented flows, regenerated `docs/dataverse-schema.md`, and updated `docs/flow-configuration.md` to remove the remaining schema-gap notes.
- Bumped `manifest.yaml` to `1.0.0-preview` and updated the verification text to reference the full lab-rebuild test.

## [0.2.0-preview] - 2026-05-06

### Changed — Microsoft Learn 2026-Q2 accuracy refresh

- Updated Microsoft Entra Agent ID handoff to the current Microsoft Graph v1.0 `POST /servicePrincipals/microsoft.graph.agentIdentity` create action with `agentIdentityBlueprintId`, sponsor binding, and create-specific permissions (`AgentIdentity.CreateAsManager` or `AgentIdentity.Create.All`).
- Updated Purview retention-label guidance: production deployments use the Purview portal or Security & Compliance PowerShell; Graph beta create is documented as delegated-only preview guidance.
- Replaced legacy HTTP-style sponsor-card actions with `Action.Submit` for the Power Automate "Post adaptive card and wait for a response" pattern.
- Aligned Power Pages and Power Automate docs with Dataverse logical names from the schema script and added the canonical Express-form/computed columns to the schema.
- Fixed Dataverse schema deployment calls to match `scripts/shared/dataverse_client.py` (`create_option_set(metadata)` and `create_column(entity, metadata)`) and added managed-identity/workload/certificate/access-token auth options.
- Updated DLP simulation to use Business, Non-business, and Blocked connector groups and detect mixed Business/Non-business connector requests.
- Changed the preview catalog tier to Tier 1 because this is a foundational pre-build intake control for agent governance, while retaining the Express path for Tier-3/Zone-3 personal-agent approvals.
- Moved smoke-test output to a repo-local `.agent-intake-smoke` folder and updated Power Pages URL examples.

## [0.1.0-preview] - 2026-05-02

### Added — Express-path MVP scaffolding

- **Manifest** — `manifest.yaml` registering the solution at `lifecycle-ops` domain, tier 3, controls 1.2/1.7/2.1/2.13/3.1
- **Dataverse schema** — `scripts/create_fsi_intake_dataverse_schema.py` defines 9 tables (`fsi_intakerequest`, `fsi_intakedatasource`, `fsi_intakerisksignal`, `fsi_intakereview`, `fsi_intakeapproval`, `fsi_intakedecisionlog`, `fsi_intakesponsorship`, `fsi_intakeauditevent`, `fsi_intakeretentionrecord`) and 7 global option sets, with `--output-docs` regenerating `docs/dataverse-schema.md`
- **Express form spec** — `docs/portal-configuration.md` documents the Power Pages Express form
- **Sponsor card** — `templates/sponsor-approval-card.json` Teams adaptive card with FINRA Rule 3110 attestation language
- **Flow build docs** — `docs/flow-configuration.md` step-by-step manual build instructions for the 3 Express-path flows (router, sponsor card, handoff). No exported flow JSON per repo Solution Content Policy.
- **Auto-detect playbook** — `docs/auto-detect-playbook.md` documents the verified Graph + PPAC endpoints used for pre-fill, and the manual fallbacks for Purview / retentionLabels
- **Auto-detect scripts** — `scripts/autodetect_environments.py`, `scripts/autodetect_dlp_simulation.py`, `scripts/autodetect_purview.py`
- **Classification rules** — `scripts/seed_classification_rules.py` seeds the Express-path tier/zone/retention auto-classification logic; `templates/policy-lookup-tables.yaml` carries the customer-overridable defaults
- **Handoff scripts** — `scripts/setup_entra_agent_id.py` (Microsoft Entra Agent ID handoff) and `scripts/setup_purview_retention_label.py` (one-time setup guidance for `FSI-AgentIntake-7yr` retention label)
- **Drift wiring** — `docs/drift-detection-integration.md` describes the integration points to `unrestricted-agent-sharing-detector`, `scope-drift-monitor`, `agent-access-monitor`, and `agent-365-lifecycle-governance`
- **Validation** — `scripts/smoke_test.ps1` end-to-end Express-path smoke test
- **Runbook** — `docs/pilot-deployment-runbook.md` step-by-step deployment + rollback procedures
- **Research artifacts** — `research/` carries the Phase A fit assessment, question-catalog evaluation, intake form design v1, API verification spike, and PO-resolved open questions (all from prior commits)
- **Adoption polish** — `docs/maker-quick-start.md`, `docs/sponsor-cheat-sheet.md`, `docs/onboarding-checklist.md`, `docs/decisions.md`, Mermaid architecture diagram added to README

### Out of scope — deferred

- **Standard path** (Tier-2/Zone-2, ~20 questions, InfoSec 10% sample dashboard) → planned for v0.3
- **Full path** (Tier-1/Zone-1, ~35 questions, parallel reviewer dashboard, MRM routing) → planned for v0.4
- **M365 Copilot declarative agent surface** (conversational intake) → planned for v0.4
- **Sovereign cloud adaptation** (GCC / GCC-High / DoD) → planned for v0.4
- **Localization** beyond en-US → post-v1.0

### Notes

- This is a **preview** release. Awaiting pilot-firm validation feedback before promoting to `live`.
- All defaults in `templates/policy-lookup-tables.yaml` are overridable per customer.
