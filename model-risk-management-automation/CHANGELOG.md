# Changelog

All notable changes to Model Risk Management Automation are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.0] — 2026-03-20

### Added

- **Dataverse Schema** — 6 custom tables: `fsi_modelinventory` (master MRM record with alternate key), `fsi_mrmriskrating` (risk scoring evidence), `fsi_validationcycle` (validation tracking), `fsi_validationfinding` (individual findings), `fsi_monitoringrecord` (ongoing monitoring), `fsi_mrmcomplianceevent` (immutable audit log)
- **Python Deployment Scripts** — `mrm_client.py` (Dataverse Web API client), `create_mrm_dataverse_schema.py` (6 tables + ~20 option sets + alternate key), `create_mrm_environment_variables.py` (27 variables), `create_mrm_connection_references.py` (6 connection references), `deploy.py` (orchestrated deployment)
- **PowerShell Scripts** — `Deploy-MRM-Baseline.ps1` (initial agent inventory export), `Validate-MRM-Compliance.ps1` (examiner-ready compliance posture report)
- **Flow Documentation** — Step-by-step build instructions for 6 Power Automate flows: Sync-AgentInventory-ToMRM (daily), Score-ModelRisk-OnSubmission (instant), Execute-ValidationWorkflow (approval-gated), Monitor-ModelPerformance-Scheduled (weekly), Generate-AgentCard-OnChange (instant), Trigger-Revalidation-OnThreshold (instant)
- **Power Apps Documentation** — Build guides for MRM Submission Portal (Canvas app, 4 screens) and Validation Workbench (Model-Driven app)
- **Power BI Documentation** — MRM Compliance Dashboard build guide with data model, DAX measures, and 5 report pages
- **SharePoint Documentation** — Agent Card Library setup with folder structure, metadata columns, permissions, and Word template configuration
- **Templates** — Adaptive Card v1.2 templates for Teams notifications (risk scoring, validation assignment, SLA breach, revalidation approval), sample configuration JSON, Agent Card content structure
- **Regulatory Alignment** — Supports OCC 2011-12 / Fed SR 11-7, SOX 302/404, FINRA Rule 3110, NIST AI RMF
- **Control Mapping** — Primary: Control 2.6 (Model Risk Management); Secondary: 2.5, 2.9, 2.11, 2.13, 3.1, 1.2
