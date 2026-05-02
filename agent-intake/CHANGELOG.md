# Changelog

All notable changes to the **agent-intake** solution will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0-preview] - 2026-05-02

### Added — Express-path MVP scaffolding

- **Manifest** — `manifest.yaml` registering the solution at `lifecycle-ops` domain, tier 3, controls 1.2/1.7/2.1/2.13/3.1
- **Dataverse schema** — `scripts/create_fsi_intake_dataverse_schema.py` defines 9 tables (`fsi_intakerequest`, `fsi_intakedatasource`, `fsi_intakerisksignal`, `fsi_intakereview`, `fsi_intakeapproval`, `fsi_intakedecisionlog`, `fsi_intakesponsorship`, `fsi_intakeauditevent`, `fsi_intakeretentionrecord`) and 6 global option sets, with `--output-docs` regenerating `docs/dataverse-schema.md`
- **Express form spec** — `docs/portal-configuration.md` documents the 10-question Power Pages Express form
- **Sponsor card** — `templates/sponsor-approval-card.json` Teams adaptive card with FINRA Rule 3110 attestation language
- **Flow build docs** — `docs/flow-configuration.md` step-by-step manual build instructions for the 3 Express-path flows (router, sponsor card, handoff). No exported flow JSON per repo Solution Content Policy.
- **Auto-detect playbook** — `docs/auto-detect-playbook.md` documents the verified Graph + PPAC endpoints used for pre-fill, and the manual fallbacks for Purview / retentionLabels
- **Auto-detect scripts** — `scripts/autodetect_environments.py`, `scripts/autodetect_dlp_simulation.py`, `scripts/autodetect_purview.py` (stub)
- **Classification rules** — `scripts/seed_classification_rules.py` seeds the Express-path tier/zone/retention auto-classification logic; `templates/policy-lookup-tables.yaml` carries the customer-overridable defaults
- **Handoff scripts** — `scripts/setup_entra_agent_id.py` (Entra Agent ID minting at handoff, GA May 1, 2026) and `scripts/setup_purview_retention_label.py` (one-time creation of `FSI-AgentIntake-7yr` retention label)
- **Drift wiring** — `docs/drift-detection-integration.md` describes the integration points to `unrestricted-agent-sharing-detector`, `scope-drift-monitor`, `agent-access-monitor`, and `agent-365-lifecycle-governance`
- **Validation** — `scripts/smoke_test.ps1` end-to-end Express-path smoke test
- **Runbook** — `docs/pilot-deployment-runbook.md` step-by-step deployment + rollback procedures
- **Research artifacts** — `research/` carries the Phase A fit assessment, question-catalog evaluation, intake form design v1, API verification spike, and PO-resolved open questions (all from prior commits)
- **Adoption polish** (added during preview) — `docs/maker-quick-start.md` (1-page maker guide), `docs/sponsor-cheat-sheet.md` (1-page sponsor guide with FINRA 3110 attestation walkthrough), `docs/onboarding-checklist.md` (single-file customer admin checklist), `docs/decisions.md` (ADR consolidating PO-locked decisions), Mermaid architecture diagram added to README

### Out of scope — deferred

- **Standard path** (Tier-2/Zone-2, ~20 questions, InfoSec 10% sample dashboard) → planned for v0.2
- **Full path** (Tier-1/Zone-1, ~35 questions, parallel reviewer dashboard, MRM routing) → planned for v0.3
- **M365 Copilot declarative agent surface** (conversational intake) → planned for v0.4
- **Sovereign cloud adaptation** (GCC / GCC-High / DoD) → planned for v0.4
- **Localization** beyond en-US → post-v1.0

### Notes

- This is a **preview** release. Awaiting pilot-firm validation feedback before promoting to `live`.
- All defaults in `templates/policy-lookup-tables.yaml` are overridable per customer.
- The Phase B-prep counter-research surfaced two material updates: OCC Bulletin 2026-13 (April 17, 2026) supersedes 2011-12 and explicitly excludes generative/agentic AI from formal MRM scope while reserving firm-level governance; Microsoft Entra Agent ID GA on May 1, 2026.
