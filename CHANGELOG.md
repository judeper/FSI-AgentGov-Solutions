# Changelog

All notable changes to FSI-AgentGov-Solutions are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Fixed

- **UASD Adaptive Card:** Corrected "Run Audit Script" URL to match actual deployment guide path; corrected "View Documentation" URL to point to Control 1.1 (was incorrectly referencing Control 2.24)

### Added

- **UASD v1.0.2** — Flow 4 (`UASD-Exception-Expiration-Monitor`) build instructions: proactive exception expiration handling with configurable warning threshold and Teams alerts
- **Deployment Guide v0.1** — Use-case mapping, solution layers, and Compliance Dashboard integration sequencing

- **DR Testing Framework v1.0.0** - Automated disaster recovery testing for AI agents
  - 4 test scenarios: Agent Restore, Environment Failover, Data Recovery, Full DR
  - RTO/RPO measurement and comparison
  - Validation checks for agent, connector, data, and security
  - PowerShell script: Invoke-DRTest.ps1
  - Gap identification and tracking
  - Evidence export for compliance
  - Supports Controls 2.4, 2.1, 1.9

- **Hallucination Tracker v1.0.0** - Feedback aggregation for hallucination pattern analysis
  - Multi-source feedback collection (user, supervisor, automated)
  - 5 hallucination categories with severity scoring
  - Pattern detection and clustering
  - Agent accuracy scoring and rating
  - Python script: analyze_patterns.py
  - Supports Controls 3.10, 2.9, 2.12

- **COI Testing Framework v1.0.0** - Conflict of interest testing for agent recommendations
  - Test categories: Proprietary bias (3), Suitability (3), Fee transparency (2), Cross-selling (2)
  - Python test runner: run_coi_tests.py
  - Scheduled and on-demand test execution
  - FINRA Supervision Workflow integration
  - Supports Controls 2.18, 2.11, 2.5

- **RAG Source Validator v1.0.0** - Integrity validation for RAG knowledge sources
  - Dataverse schema: fsi_knowledgesource, fsi_validationresult, fsi_sourcechange
  - Security roles: RSV Viewer, RSV Validator, RSV Admin
  - PowerShell script: Invoke-SourceValidation.ps1
  - SHA-256 hash validation, schema drift detection, freshness monitoring
  - Supports SharePoint, Dataverse, Azure Blob sources
  - Supports Controls 2.16, 1.7, 2.13

- **Scope Drift Monitor v1.0.0** - Detect agent data access beyond declared scope
  - Dataverse schema: fsi_agentscope, fsi_scopeitem, fsi_scopeviolation, fsi_expansionrequest
  - Security roles: SDM Viewer, SDM Analyst, SDM Admin
  - PowerShell script: New-AgentBaseline.ps1
  - Scope expansion workflow with data owner and security approval
  - Complete documentation: prerequisites, schema, baseline configuration
  - Supports Controls 1.14, 1.4, 1.5

- **Segregation of Duties Detector v1.0.0** - Role conflict detection for Maker/Checker enforcement
  - Dataverse schema: fsi_conflictrule, fsi_sodviolation, fsi_sodexception, fsi_sodauditlog
  - Security roles: SoD Viewer, SoD Analyst, SoD Admin
  - PowerShell scripts: Invoke-SoDScan.ps1, Import-ConflictRules.ps1
  - Default rule sets: Maker/Checker (4), Segregation (3), Privileged Access (3)
  - Complete documentation: prerequisites, schema, conflict rules, troubleshooting
  - Supports Controls 2.8, 2.1, 2.3

- **Compliance Dashboard v1.0.0-beta** - Aggregated compliance reporting across 71 controls
  - Dataverse schema: fsi_controlmaster, fsi_controlassessment, fsi_compliancescore, fsi_complianceexception, fsi_complianceevidence
  - Security roles: CD Viewer, CD Assessor, CD Admin
  - Power Automate flows: CD-ScoreCalculator, CD-ExceptionMonitor, CD-EvidenceCollector
  - Python script: load_sample_data.py for demo data
  - Complete documentation: prerequisites, schema, flows, Power BI setup, DAX measures, troubleshooting
  - Control master data: All 71 controls with zone applicability and weights
  - Supports Controls 3.3, 3.1, 3.2
  - **Note:** Beta release - documentation and schemas complete, Power BI template requires manual creation

- **Conditional Access Automation v1.0.0** - CA policy deployment and compliance monitoring for AI workloads
  - 8 policy templates for Copilot Studio, Agent Builder, and M365 Copilot
  - PowerShell scripts: Deploy-CAPolicies.ps1, Test-PolicyCompliance.ps1, Register-ServicePrincipal.ps1
  - Zone-based policy requirements (Zone 1: risk-based, Zone 2: always MFA, Zone 3: MFA + compliant device)
  - Policy drift detection and compliance monitoring
  - Break-glass account exclusion enforcement
  - ELM integration for automated policy deployment on environment provisioning
  - Complete documentation: prerequisites, templates, deployment guide, compliance monitoring, troubleshooting
  - Supports Controls 1.11, 1.23, 1.18

- **FINRA Supervision Workflow v1.0.0** - Automated supervision queue for AI agent outputs (FINRA 3110)
  - Dataverse schema: SupervisionQueue, SupervisionLog, SupervisionConfig tables
  - Security roles: FSW Supervisor, FSW Queue Manager, FSW Admin, FSW Auditor
  - Python scripts: deploy.py, export_supervision_evidence.py
  - Complete documentation: prerequisites, schema, security roles, flow configuration, Communication Compliance setup, Power BI dashboard, troubleshooting
  - Integration with Communication Compliance API for flagged content ingestion
  - Zone/tier-based SLA configuration with automatic escalation
  - Evidence export with SHA-256 integrity hashing for regulatory examination
  - Supports Controls 2.12, 1.10, 1.7

- **Environment Lifecycle Management v1.0.1** - Automated Power Platform environment provisioning
  - Python scripts: Service Principal registration, quarterly evidence export, role verification, immutability validation
  - Complete documentation: prerequisites, Dataverse schema, security roles, flow configuration, Copilot setup
  - Templates: EnvironmentRequest JSON sample, Copilot Studio output schema
  - SETUP_CHECKLIST.md for phased deployment

### Changed

- Updated root README.md to include Environment Lifecycle Management
- Enhanced boundary-check.py hook with cross-repository access to FSI-AgentGov
- Added Python/pip permissions to settings.json
- Added hooks configuration to settings.json (previously only in settings.local.json)

---

## Previous Releases

Individual solution changelogs:

- [DR Testing Framework](./dr-testing-framework/CHANGELOG.md) - v1.0.0
- [Hallucination Tracker](./hallucination-tracker/CHANGELOG.md) - v1.0.0
- [COI Testing Framework](./coi-testing/CHANGELOG.md) - v1.0.0
- [RAG Source Validator](./rag-source-validator/CHANGELOG.md) - v1.0.0
- [Scope Drift Monitor](./scope-drift-monitor/CHANGELOG.md) - v1.0.0
- [Segregation of Duties Detector](./segregation-detector/CHANGELOG.md) - v1.0.0
- [Compliance Dashboard](./compliance-dashboard/CHANGELOG.md) - v1.0.0-beta
- [Conditional Access Automation](./conditional-access-automation/CHANGELOG.md) - v1.0.0
- [FINRA Supervision Workflow](./finra-supervision-workflow/CHANGELOG.md) - v1.0.0
- [Environment Lifecycle Management](./environment-lifecycle-management/CHANGELOG.md) - v1.1.2
- [Message Center Monitor](./message-center-monitor/CHANGELOG.md) - v2.1.1
- [Pipeline Governance Cleanup](./pipeline-governance-cleanup/CHANGELOG.md) - v1.0.8
- [Deny Event Correlation Report](./deny-event-correlation-report/CHANGELOG.md) - v1.1.0
