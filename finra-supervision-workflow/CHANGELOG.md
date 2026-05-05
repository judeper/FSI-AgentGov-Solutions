# Changelog

All notable changes to the FINRA Supervision Workflow solution are documented here.

## [Unreleased]

### Changed

- **Microsoft Learn 2026-Q2 refresh** — updated Power Automate Approvals, Teams Adaptive Cards, Outlook Actionable Messages, Purview Communication Compliance, eDiscovery, records-management, and WORM storage guidance.
- **Managed identity-first authentication** — deployment and evidence export now default to managed identity/workload identity, with client-secret authentication marked as a legacy dev-only fallback.
- **Evidence retention guidance** — clarified that Dataverse SupervisionLog is append-only by role design and that WORM preservation requires locked Azure Blob immutability policies or Microsoft Purview records-management labels.
- **Review response capture** — documented current Approvals connector response outputs, parallel approval patterns, and Teams/Outlook Adaptive Card requirements.

## [1.0.1] - 2026-04-16

### Fixed

- **Status downgraded from Validated to Preview** — pending verification of Purview Communication Compliance ingestion endpoint and addition of automated column-creation in deploy.py.
- **Scope clarification** — README now states this solution provides the **retrospective** supervision arm of Control 2.12; pre-delivery HITL for Zone 3 agents is provided by hitl-workflow-governance.
- **Control 2.12 link** — corrected to `2.12-supervision-and-oversight-finra-rule-3110.md` (was 404).
- **Power BI control 3.3 link** — corrected to `3.3-compliance-and-regulatory-reporting.md` (was 404).
- **Retention overstatement** — split SEC 17a-4(b)(4) communications retention (3 years) from FINRA 4511(b) (6 years) instead of blanket `minimum 6 years`.
- **deploy.py truth-in-advertising** — README Step 1 now explicitly says deploy.py creates only table shells; columns must be created manually with explicit small-integer option-set values.
- **Power Automate `rand` off-by-one** — `rand(1, 100)` upper bound is exclusive; flow-configuration.md updated to `rand(1, 101)` with explanatory note. `.ralph-config.json` fact updated.
- **Lookup columns stored as text** — flow-configuration.md SupervisionLog creation steps now use `fsi_actor@odata.bind` and `fsi_queueitem@odata.bind` to `/systemusers(...)` and `/fsi_supervisionqueues(...)` instead of display strings.
- **Placeholder agent metadata URL** — `https://api.powerplatform.com/...` replaced with concrete guidance pointing to agent-registry-automation, environment-lifecycle-management, or a static mapping table.
- **Source-type label drift** — README aligned to `Manual Entry` (matches schema and deploy.py).
- **Evidence export artifact list** — added `SupervisionConfig-{period}.json` and `manifest-{period}.sha256` to README's documented exports (script already produces these).
- **Quick Start dependency** — added `pip install pytest` to enable running `test_export_supervision_evidence.py` per the documented command.
- **HTML TODO comment** removed from README.

### Notes

- AI Council technical-accuracy pass (Opus 4.7 + Goldeneye + GPT-5.4).

## [1.0.0] - 2026-02-15

### Added

- Initial release
- SupervisionQueue table with 17 columns
- SupervisionLog table for immutable audit trail
- SupervisionConfig table for zone/tier-based rules
- Four security roles (Supervisor, Queue Manager, Admin, Auditor)
- Deployment script (`deploy.py`)
- Evidence export script (`export_supervision_evidence.py`)
- ~~FINRA 3120 report generator (`generate_3120_report.py`)~~ — Planned for a future release (see README)
- Power BI dashboard setup guide (template planned for future release)
- Integration with Communication Compliance API
- Documentation suite (prerequisites, schema, flows, troubleshooting)

### Regulatory Alignment

- FINRA Rule 3110 supervision routing
- FINRA Rule 3120 testing evidence
- FINRA Notice 24-09 AI communication supervision
- SEC 17a-3/4 recordkeeping

### Known Limitations

- Communication Compliance polling (not real-time webhook)
- Manual Power BI deployment required
- Zone/tier configuration via model-driven app only
