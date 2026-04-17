# Changelog

All notable changes to Model Risk Management Automation are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.2] — 2026-04-16

### Fixed

- **Dataverse column drift in flow-configuration.md** — corrected child-table OData filters to use lookup columns (`_fsi_modelinventory_lookup_value eq <guid>`, `_fsi_validationcycle_lookup_value eq <guid>`) instead of nonexistent FK fields like `fsi_modelinventoryid eq '<guid>'`; replaced row-create assignments with `@odata.bind` syntax for lookup relationships.
- **Picklist values shown as text labels** — converted all `fsi_cyclestatus`, `fsi_validationstatus`, and `fsi_mrmstatus` references in flow-configuration.md from text labels (`"In Progress"`, `"Findings Issued"`) to integer option-set values (`100000003`, `100000004`) that match `create_mrm_dataverse_schema.py`. Includes inline notes for option sets that are 1-based vs 0-based.
- **`fsi_governancezone` references** — corrected to `fsi_zone` (option set `fsi_acv_zone`), the actual column name in agent-registry-automation and MRM schema.
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
