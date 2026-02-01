# Changelog

All notable changes to FSI-AgentGov-Solutions are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added

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

- [FINRA Supervision Workflow](./finra-supervision-workflow/CHANGELOG.md) - v1.0.0
- [Environment Lifecycle Management](./environment-lifecycle-management/CHANGELOG.md) - v1.1.2
- [Message Center Monitor](./message-center-monitor/CHANGELOG.md) - v2.1.1
- [Pipeline Governance Cleanup](./pipeline-governance-cleanup/CHANGELOG.md) - v1.0.8
- [Deny Event Correlation Report](./deny-event-correlation-report/CHANGELOG.md) - v1.1.0
