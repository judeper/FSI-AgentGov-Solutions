# Changelog

All notable changes to the Unrestricted Agent Sharing Detector are documented here.

## [1.0.1] — February 2026

### Changed
- Removed `src/` directory with exported flow JSON per Solution Content Policy — flows are now built manually using `docs/flow-configuration.md`
- Removed `DELIVERY-CHECKLIST.md` (no longer applicable without exported artifacts)
- Shared Dataverse client (`scripts/shared/dataverse_client.py`) replaces solution-specific `uasd_client.py`
- Schema script generates `docs/dataverse-schema.md` via `--output-docs` flag
- Trimmed SOLUTION-DOCUMENTATION.md to reference generated schema docs

## [1.0.0] — February 2026

### Added
- Detector scan flow for continuous monitoring of agent sharing configurations
- Remediation flow for automated policy enforcement
- Exception approval workflow for business-justified exceptions
- Exception manager Canvas app for exception lifecycle management
- Teams adaptive card alert for real-time violation notifications
- Dataverse schema setup scripts, environment variables, connection references
- PowerShell governance scripts for sharing audit, violation export, and security group import
