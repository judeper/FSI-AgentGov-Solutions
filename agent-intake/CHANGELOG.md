# Changelog

All notable changes to the **agent-intake** solution will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0-preview] - 2026-05-16

### Added

- Added the v1.0.0-preview schema and policy foundations for three intake paths, including new option sets, status values, audit event inventories, and routing columns such as `fsi_routingtopology`, `fsi_quorumrequired`, `fsi_parallelreviewersjson`, `fsi_mrmrequired`, `fsi_mrmhandoffstatus`, `fsi_standardfullquestionsjson`, `fsi_appealofid`, and `fsi_nonmrmquorummet` (`f10cabe`).
- Added refreshed Express questions plus the new Standard and Full question catalogs, including 22 Standard questions, 35 Full questions, and the overview map that explains when each pack is used (`4dfc9d0`).
- Added drift-detection handoff payload guidance for Standard and Full paths so downstream monitoring solutions can consume richer post-approval context (`2632f5a`).
- Added Microsoft Entra Agent ID blueprint automation with the `fsiReviewerAttestations` open-type payload pattern and extended Purview retention-label automation to cover reviewer attestations in the decision pack (`fa411b4`).
- Added MRM handoff integration to `model-risk-management-automation`, including alternate-key lookup guidance for `fsi_modelinventory` and status tracking for the intake handoff (`8f41f90`).
- Added a model-driven reviewer queues app and ADR-011 implementation notes, with the managed `.zip` artifact explicitly permitted for this app-only packaging scenario (`9f76e15`).
- Added a dedicated CI workflow with four validators and 42 pytest cases to keep the preview lab rebuild and schema docs aligned (`9f177be`).
- Added a full enablement suite for makers, sponsors, reviewers, admins, and demo operators so pilot teams can rehearse all three paths before broad rollout (`18dc8cf`).

### Changed

- Changed the classification model from Express-only routing to Express, Standard, and Full paths, with refreshed Express logic and policy mapping that now supports reviewer quorum, non-MRM quorum tracking, and MRM-required escalation (`6570da8`).
- Changed the maker experience to a multistep Power Pages form with progressive disclosure, plus PAC CLI scaffolding for the portal assets that can be automated today (`5a24d1b`).
- Changed the build guidance from the original Express-only flow set to 12 documented Power Automate flows (build instructions only, no exported JSON per repo policy), plus supporting PAC shell and prerequisites guidance (`1adf2d8`).
- Changed lab operations to a single-command `deploy.ps1` orchestrator with `-Teardown`, `-SeedTestData`, and `-DryRun`, five test data fixtures, and an expanded `smoke_test.ps1` with `-PathScope` and `-IncludeSeededDataChecks` (`3bc5400`).

### Removed

- Removed the remaining schema-gap caveats from the flow build guide once the missing request columns, status values, and audit-event inventories were added to the Dataverse model (`9461a38`).

### Fixed

- Fixed release-adjacent reconciliation issues across catalog field references, ruff `E402`, and `Write-Host` usage so the preview content is internally consistent for the v1.0.0-preview drop (`c1e32ec`).
- Fixed flow-spec-driven schema gaps by closing the open items around `fsi_appealofid`, the extra intake statuses, `fsi_nonmrmquorummet`, and the newer audit event values, then regenerating `docs/dataverse-schema.md` to match (`9461a38`).

### Security

- Extended records and identity automation so reviewer attestations, sponsor approvals, and Agent ID minting events can be retained and replayed as part of the same decision pack, which supports compliance with FINRA Rule 4511(a), SEC Rule 17a-4, and CFTC Rule 1.31 when customers complete the tenant-side retention and approval setup (`fa411b4`).

### Known limitations / v1.1 evolution

- `fsi_appealofid` is currently a Single Line of Text column; convert it to a self-lookup in v1.1.
- Microsoft Entra Agent ID `fsiReviewerAttestations` open-type field acceptance is pending live-tenant verification.
- PAC CLI cannot programmatically create Power Pages multistep form bindings; Stage 4 of `deploy.ps1` includes **MANUAL STEP REQUIRED** markers.
- Two legacy PSScriptAnalyzer warnings in `provision_power_pages.ps1` remain soft-gated as the current baseline.

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
