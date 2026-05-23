# Changelog

All notable changes to Model Risk Management Automation are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.4] — 2026-05-23

### Fixed

- **Critical**: Flow 2 step 3.7 Change Frequency Score used a nonexistent lookup `_fsi_validationcycle_lookup_value` on `fsi_mrmcomplianceevent`; corrected to `_fsi_modelinventory_lookup_value eq @{model.id}` per the schema (only `fsi_ModelInventory_Lookup` exists on that table). `docs/flow-configuration.md` ~line 355. (council review C-1)
- **Critical**: Troubleshooting diagnostic queries "List Open Validation Cycles" and "Recent Compliance Events" referenced nonexistent `fsi_modelid` on `fsi_validationcycle` / `fsi_mrmcomplianceevent`; replaced with the actual lookup column `_fsi_modelinventory_lookup_value`. `docs/troubleshooting.md` lines 206-207, 213-214. (council review C-2)
- **Major**: `create_mrm_dataverse_schema.py` `create_alternate_keys()` bypassed the client abstraction by calling `client.session.get/post()` and constructing raw EntityDefinitions URLs; replaced with `client.ensure_entity_key()` from the shared client. (council review M-4)
- **Major**: Flow 2 steps 3.4 (Model Complexity) and 3.5 (Explainability) compared `fsi_modelprovider` / `fsi_decisionoutputtype` picklist columns against string labels; added the same "Use OptionSet integer values for comparison in production" note that step 3.1 already carries, including the integer mapping table. `docs/flow-configuration.md`. (council review M-5)

### Changed

- **Major**: `mrm_client.py` (534 lines) is now a deprecation stub that raises `ImportError`; all four internal callers (`create_mrm_dataverse_schema.py`, `create_mrm_environment_variables.py`, `create_mrm_connection_references.py`, `deploy.py`) now import the shared `DataverseClient` from `scripts/shared/dataverse_client.py`. Eliminates ~400 lines of duplicated MSAL/retry/metadata-CRUD logic and inherits the shared client's `_raise_for_status()`, `update_record()`, `delete_record()`, `ensure_entity_key()` helpers and future improvements. (council review M-1)
- **Major**: Option-set lookup is now case-insensitive (`name.lower()` normalization) via the shared `DataverseClient.get_global_optionset()`; prevents latent `SchemaNameisNotUnique` errors if any caller ever passes mixed-case names. (council review M-2)
- Added `_build_optionset_metadata`, `_build_table_metadata`, `_build_column_metadata` module-level helpers to `create_mrm_dataverse_schema.py` mirroring the CTSG template; gives a stable contract layer for future shared-client work.
- Constructed `DataverseClient` in live mode (no `dry_run=` passed to constructor) following the Wave 1 CTSG lesson (`migrate_ctsg_optionsets_v1_1_0.py:238-267`); reads execute live so existence checks remain meaningful in `--dry-run`, while every write is gated locally with explicit `if dry_run:` branches.

### Notes

- M-3 (rename `fsi_mrm_sr117pillar` option set to `fsi_mrm_sr262pillar`) is **deferred to MRM v1.0.5** as a `[BREAKING DEPLOY]` minor bump with a dedicated migration script, following the Wave 1 CTSG precedent (scope-discipline: defer breaking-deploy work out of patch bumps).
- Schema column names, regulatory references, and the deprecated `mrm_client.py` are unchanged on disk other than the stub conversion; no tenant-side re-keying is required for this release. Operators upgrading from v1.0.3 should re-run `pip install -r scripts/requirements.txt` so the shared client's `azure-identity` is available where it was not previously.

---

## [1.0.3] — 2026-05-05

### Fixed

- **MRM governance-zone mapping** — corrected Flow 1, Flow 2, and Agent Card instructions to map source `fsi_agentinventory.fsi_zone` into target `fsi_modelinventory.fsi_governancezone`, matching `create_mrm_dataverse_schema.py` and generated schema docs.
- **Invalid Agent Card JSON sample** — removed the JavaScript-style comment and expanded the sample with Microsoft Learn 2026-Q2 evidence fields for Agent ID, Agent 365 package metadata, model card source details, Foundry evaluation runs, and Compliance Manager caveats.
- **Agent registry API drift** — replaced the obsolete Agent Registry agents endpoint reference with current preview Agent 365 package APIs and legacy `/beta/agentRegistry/agentInstances` convergence notes.

### Changed

- **Managed-identity-first Python authentication** — added Azure Identity `DefaultAzureCredential` support for managed identity/workload identity, kept interactive auth for admin workstations, and marked client-secret authentication as legacy dev-only.
- **Configurable risk thresholds** — added `fsi_MRM_RiskScoreCriticalThreshold`, `fsi_MRM_RiskScoreHighThreshold`, and `fsi_MRM_RiskScoreMediumThreshold` environment variables and updated Flow 2 guidance to use institution-calibrated thresholds.
- **Power Automate approval guidance** — clarified Dataverse-backed split-flow patterns for validation approvals that can exceed the 30-day connector timeout.

---

## [1.0.2] — 2026-04-16

### Fixed

- **Dataverse column drift in flow-configuration.md** — corrected child-table OData filters to use lookup columns (`_fsi_modelinventory_lookup_value eq <guid>`, `_fsi_validationcycle_lookup_value eq <guid>`) instead of nonexistent FK fields like `fsi_modelinventoryid eq '<guid>'`; replaced row-create assignments with `@odata.bind` syntax for lookup relationships.
- **Picklist values shown as text labels** — converted all `fsi_cyclestatus`, `fsi_validationstatus`, and `fsi_mrmstatus` references in flow-configuration.md from text labels (`"In Progress"`, `"Findings Issued"`) to integer option-set values (`100000003`, `100000004`) that match `create_mrm_dataverse_schema.py`. Includes inline notes for option sets that are 1-based vs 0-based.
- **Governance-zone references** — clarified that `fsi_agentinventory.fsi_zone` is the source column from agent-registry-automation and `fsi_modelinventory.fsi_governancezone` is the MRM target column, both using option set `fsi_acv_zone`.
- **Agent Card section column drift** — fixed `model.fsi_agentid` → `model.fsi_modelid` in SharePoint folder/file paths; removed nonexistent `fsi_validatordisplayname`, `fsi_ownerdisplayname`, `fsi_environmentname`, `fsi_limitations`, `fsi_agentcardgenerateddate` references; aligned to schema columns with notes on resolving display names from Microsoft Graph at read time.
- **Monitoring record column names** — `fsi_outofscopecount` → `fsi_outofscopetriggers`; `fsi_thresholdbreached` → `fsi_thresholdbreachflag`; `fsi_cycleopeneddate` → `fsi_submitteddate`; `fsi_cyclecloseddate` → `fsi_validationcompleteddate`.
- **Control 3.1 mapping** — updated title from "Audit Logging" to "Agent Inventory and Metadata Management" (canonical FSI-AgentGov framework title) and corrected URL slug.
- **Pillar 2 URL paths** — corrected from nonexistent `pillar-2-governance/` to `pillar-2-management/` for all secondary control links.
- **Quick Start auth parameters** — added missing `--client-id` / `--client-secret` parameters to environment variable and connection reference deployment commands in README.
- **Version history** — corrected README to show 1.0.0 as the initial release (was incorrectly attributed to 1.0.1).

### Changed

- **Regulatory language softening** — removed "examiner-facing" in favor of "examiner-facing"; softened "Both [OCC 2011-12 and SR 11-7] have been confirmed to apply to ... LLMs and agentic AI" to reflect that the 2021 Interagency RFI confirmed applicability to traditional ML, with LLM/agentic AI guidance still evolving.
- **FINRA Rule 3110 framing** — replaced overclaim "three-lines-of-defense role enforcement" with concrete description of maker/checker/approver role separation in the validation workflow.
- **"enforces" → "applies/supports"** — softened control-language in regulatory cells per FSI language rules.
- **Zone-change material-change criterion** — Flow 1 step 4.5.1 criterion (d) now uses `fsi_zone` (matching agent-registry-automation column).
- **fsi_validatordepartment** captured at validation assignment instead of nonexistent `fsi_validatordisplayname`. Display names resolved at read-time from Microsoft Graph via `fsi_validatorupn`.

### Notes

- Source-of-truth reminder: column names and option set values in this solution are defined in `scripts/create_mrm_dataverse_schema.py`. All flow build instructions and downstream documentation must match that file.

---

## [1.0.1] — 2026-04-15

### Fixed

- Fixed option set default values for Dataverse picklist columns
- Renamed Validate-MRM-Compliance.ps1 to Test-MRMCompliance.ps1 (approved PowerShell verb)

---

## [1.0.0] — 2026-03-20

### Added

- **Dataverse Schema** — 6 custom tables: `fsi_modelinventory` (master MRM record with alternate key), `fsi_mrmriskrating` (risk scoring evidence), `fsi_validationcycle` (validation tracking), `fsi_validationfinding` (individual findings), `fsi_monitoringrecord` (ongoing monitoring), `fsi_mrmcomplianceevent` (immutable audit log)
- **Python Deployment Scripts** — `mrm_client.py` (Dataverse Web API client), `create_mrm_dataverse_schema.py` (6 tables + ~20 option sets + alternate key), `create_mrm_environment_variables.py` (27 variables), `create_mrm_connection_references.py` (6 connection references), `deploy.py` (orchestrated deployment)
- **PowerShell Scripts** — `Deploy-MRM-Baseline.ps1` (initial agent inventory export), `Test-MRMCompliance.ps1` (examiner-facing compliance posture report)
- **Flow Documentation** — Step-by-step build instructions for 6 Power Automate flows: Sync-AgentInventory-ToMRM (daily), Score-ModelRisk-OnSubmission (instant), Execute-ValidationWorkflow (approval-gated), Monitor-ModelPerformance-Scheduled (weekly), Generate-AgentCard-OnChange (instant), Trigger-Revalidation-OnThreshold (instant)
- **Power Apps Documentation** — Build guides for MRM Submission Portal (Canvas app, 4 screens) and Validation Workbench (Model-Driven app)
- **Power BI Documentation** — MRM Compliance Dashboard build guide with data model, DAX measures, and 5 report pages
- **SharePoint Documentation** — Agent Card Library setup with folder structure, metadata columns, permissions, and Word template configuration
- **Templates** — Adaptive Card v1.2 templates for Teams notifications (risk scoring, validation assignment, SLA breach, revalidation approval), sample configuration JSON, Agent Card content structure
- **Regulatory Alignment** — Supports OCC 2011-12 / Fed SR 11-7, SOX 302/404, FINRA Rule 3110, NIST AI RMF
- **Control Mapping** — Primary: Control 2.6 (Model Risk Management); Secondary: 2.5, 2.9, 2.11, 2.13, 3.1, 1.2
