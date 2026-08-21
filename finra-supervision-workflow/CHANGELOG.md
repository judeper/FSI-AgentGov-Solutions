# Changelog

All notable changes to the FINRA Supervision Workflow solution are documented here.

## [Unreleased]

## [1.1.2] - 2026-08-21

### Changed

- Replace the mutable `deploy_all` flag with explicit command-line mode predicates so CodeQL can verify each deployment branch without changing default or selective deployment behavior.
- **docs**: Corrected `az keyvault create` example in `docs/prerequisites.md` — removed the non-existent `--enable-soft-delete true` flag (soft delete is always enabled and cannot be disabled, so the flag was removed from `az keyvault create`) and added `--retention-days 90` for the soft-delete retention window. (second-pass command-existence validation)
- **docs**: Replaced the deprecated `Get-SupervisoryReviewPolicy` cmdlet with the documented `Get-SupervisoryReviewPolicyV2` in `docs/communication-compliance-setup.md` (Steps 5 and 6). The non-V2 cmdlet page is no longer published on Microsoft Learn (404); README and flow-configuration.md already used the V2 cmdlet. (second-pass command-existence validation)
- **docs**: Corrected Power BI refresh-cadence guidance in `docs/power-bi-setup.md`. A 30-minute refresh cadence (48 refreshes/day) requires Power BI Premium / Premium Per User; semantic models on shared capacity (Power BI Pro) are limited to 8 refreshes/day. Replaced the contradictory "Frequency: Daily / every 30 minutes" table with capacity-based guidance and an authoritative Microsoft Learn citation. (lab-readiness validation)

### Added

- **docs**: Added `LAB-VALIDATION.md` evidence report documenting static validation (parse-validity, authoritative-source verification, doc completeness) for lab-readiness. (lab-readiness validation)

## [1.1.1] - 2026-05-23

### Changed

- **Major**: Extracted state/outcome/zone magic numbers in `export_supervision_evidence.py` and `test_export_supervision_evidence.py` to named module-level constants (`STATE_PENDING`, `STATE_APPROVED`, `OUTCOME_APPROVED`, `ZONE_1`, etc.). Centralizes the option-set value contract and makes schema drift easier to spot. `scripts/export_supervision_evidence.py:138-186`. (council review M-3)
- **Minor**: Added a host-pattern warning (non-fatal) for `--environment-url` in both `deploy.py` and `export_supervision_evidence.py`. Accepts commercial (`*.crm*.dynamics.com`) and US/DE sovereign Dataverse host suffixes; prints a warning for non-matching URLs so users catch typos before authentication fails. `scripts/deploy.py`, `scripts/export_supervision_evidence.py`. (council review minor-5)
- **Minor**: Added an inline note in `deploy.py` clarifying that `fsi_supervisionconfigs` is the default Dataverse-pluralized `EntitySetName` for `fsi_supervisionconfig`. (council review minor-1)

### Added

- **Major**: Added `pytest>=7.0.0` to `scripts/requirements.txt` so the documented `python -m pytest test_export_supervision_evidence.py -v` command works after `pip install -r requirements.txt`. (council review M-4)

### Deferred (tracked for follow-up PRs)

- **M-1 — option-set value migration (0/1/2/3 -> 100000000+)**: deferred to a future `v1.2.0 [BREAKING DEPLOY]` per repo patch-scope policy. The current small-integer scheme is internally self-consistent across schema, deploy script, export script, Power BI DAX, and flow docs, and the README Step 1.5 instructs operators to use these values explicitly.
- **M-2 — refactor `deploy.py` to import shared `DataverseClient`**: deferred. The local 70-line client is functionally adequate for the deploy script's three call sites (`get_entity_metadata`, `create_entity`, `create_record`); the refactor adds runtime risk without correcting a functional bug. Tracked for a coordinated cross-solution shared-client adoption pass.
- **minor-2 (HTML sanitization note), minor-3 (DAX inline comment), minor-6 (auth-flow factoring), minor-7 (security-roles doc clarification), minor-8 (FINRA Notice 24-09 citation polish)**: doc-only / refactor-only findings deferred per minor-deferral rubric. minor-4 (CLAUDE.md v1.0.1) was investigated and is a **FALSE POSITIVE** — CLAUDE.md already lists v1.1.0.

## [1.1.0] - 2026-05-04

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
