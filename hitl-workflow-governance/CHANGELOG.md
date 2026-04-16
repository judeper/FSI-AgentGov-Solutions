# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [1.0.1] - 2026-04-15

### Fixed

- Critical: Write-HWGValidationHistory -> Write-HitlScanRun, Write-HWGViolation -> Write-HitlViolation (function names now match module exports)
- Write-Output contamination in Object output mode changed to Write-Host

## [1.0.0] - 2026-04-01

### Added

- HITL checkpoint detection engine scanning agent flows for Request for Information and Run a Multistage Approval actions
- Zone-based HITL policy evaluation (Zone 1 advisory, Zone 2 conditional, Zone 3 mandatory)
- Dataverse schema with three tables: fsi_HitlCheckpointResult, fsi_HitlCheckpointException, fsi_HitlScanRun
- Python deployment scripts: schema, environment variables, connection references, orchestrator
- PowerShell governance scripts: scan, compliance test, evidence export, integrity verification
- Azure Automation runbook wrapper with drift detection
- SHA-256 evidence export with manifest for regulatory examination
- Teams adaptive card notification template
- Zone policy configuration template
- Private PowerShell helper modules for Dataverse operations and zone classification
- Documentation: prerequisites, flow configuration (manual build), Dataverse schema, troubleshooting

### Regulatory Alignment

- Supports FINRA Rule 3110 supervision requirements for human review of AI agent outputs
- Aids in FINRA 4511 record retention for supervision evidence
- Helps meet SEC 17a-3/4 documentation requirements for supervisory review
- Supports SOX 302/404 internal control documentation
- Aids in GLBA 501(b) safeguards for customer financial information processing

### Known Limitations

- Microsoft Human in the Loop connector actions (Request for Information, Run a Multistage Approval) are currently in public preview
- Scan detection relies on bot component definitions; flows without saved definitions may not be detected
- Reviewer response content is not captured by scan scripts (only checkpoint presence/absence)
- Zone classification requires Environment Lifecycle Management deployment or naming convention adherence
