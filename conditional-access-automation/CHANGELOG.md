# Changelog

All notable changes to the Conditional Access Automation solution are documented here.

## [1.2.0] - 2026-04-02

### Added
- Dataverse schema deployment script with 3 tables, 2 option sets, and `--output-docs` support
- Environment variables script (16 variables for scan config, notifications, Azure infra)
- Connection references script (Dataverse, Office 365, Teams)
- Python requirements.txt

### Changed
- Implemented all 8 CAAClient.psm1 Dataverse functions (previously stubs)
- Implemented Start-CAAValidationRunbook.ps1 (previously NotImplemented placeholder)
  - Full Azure Automation orchestration: auth, compliance checks, drift detection, Dataverse persistence
  - Structured JSON output for Power Automate integration

## [1.1.2] - 2026-07-15

### Changed
- Moved adaptive card template from `src/` to `templates/` (repository content policy alignment)
- Removed `src/caa-daily-compliance-flow.json` and `src/caa-provisioning-hook-flow.json` flow exports (see `docs/` for manual build instructions)
- Removed `src/` directory — solutions provide documentation and scripts, not Power Platform runtime artifacts

## [1.1.1] - 2026-03-13

### Fixed
- Updated `Get-AzAccessToken` fallback in Export-CAAComplianceEvidence.ps1 to use `-AsSecureString` pattern (Az module 12+ compatibility)
- Added Common zone (M365Copilot, BlockLegacyAuth) to coverage tracking in Test-PolicyCompliance.ps1
- Fixed Watch-PolicyDrift.ps1 `-BaselinePath` examples across README and docs to show file path instead of directory
- Updated GLBA regulatory citation to reference FTC Safeguards Rule (16 CFR Part 314)

## [1.1.0] - 2026-02-10

### Added
- CAAClient PowerShell module with 8 Dataverse functions (Connect, Read, Write)
- Azure Automation runbook (Start-CAAValidationRunbook.ps1) for unattended daily execution
- Power Automate daily compliance scan flow (caa-daily-compliance-flow.json)
- ELM provisioning hook flow (caa-provisioning-hook-flow.json)
- Teams adaptive card alert template (adaptive-card-caa-alert.json)
- Dataverse schema: 3 tables (Baseline, ValidationHistory, Violation)
- 7 environment variables with fsi_CAA_* prefix
- 3 connection references with fsi_cr_* naming (Graph connector planned)
- Multi-dimensional drift detection (state, conditions, grants, sessions, additions/removals)
- SHA-256 evidence export (Export-CAAComplianceEvidence.ps1)
- Evidence integrity verification (Test-EvidenceIntegrity.ps1)
- Policy baseline export (Export-PolicyBaseline.ps1)
- Policy drift monitoring (Watch-PolicyDrift.ps1)
- Zone lookup integration with ELM Dataverse
- Dry-run mode for all deployment operations
- PREREQUISITES.md, SCHEMA.md, EVIDENCE_EXPORT.md documentation

### Changed
- Deploy-CAPolicies.ps1 modernized with module structure and WhatIf support
- Test-PolicyCompliance.ps1 extended with Dataverse persistence and drift analysis
- Register-ServicePrincipal.ps1 modernized with Key Vault integration
- Module manifest updated with Tier 2 function exports

## [1.0.0] - February 2026

### Added

- Initial release
- 9 Conditional Access policy templates for AI workloads
- PowerShell deployment scripts with Graph API integration
- Compliance verification and gap analysis
- Policy drift detection with Teams alerting
- Evidence export with SHA-256 integrity hashing
- ELM integration for automated policy deployment
- Documentation suite (prerequisites, templates, deployment, monitoring, troubleshooting)

### Policy Templates

| Template | Target Application | Zone |
|----------|-------------------|------|
| CA-CopilotStudio-Zone1 | Copilot Studio | Zone 1 |
| CA-AgentBuilder-Zone1 | Agent Builder | Zone 1 |
| CA-CopilotStudio-Zone2 | Copilot Studio | Zone 2 |
| CA-CopilotStudio-Zone3 | Copilot Studio | Zone 3 |
| CA-AgentBuilder-Zone2 | Agent Builder | Zone 2 |
| CA-AgentBuilder-Zone3 | Agent Builder | Zone 3 |
| CA-M365Copilot-AllZones | M365 Copilot | All |
| CA-BlockLegacyAuth-AI | All AI apps | All |
| CA-RequireCompliantDevice-Zone3 | Zone 3 apps | Zone 3 |

### Scripts

- `Register-ServicePrincipal.ps1` - Service principal setup
- `Deploy-CAPolicies.ps1` - Template deployment
- `Test-PolicyCompliance.ps1` - Coverage verification
- `Watch-PolicyDrift.ps1` - Drift detection
- `Export-CAAComplianceEvidence.ps1` - Compliance evidence

### Security Alignment

- Zero Trust architecture (verify explicitly)
- NIST 800-53 AC-2, IA-2 controls
- SOX 404 IT general controls
- GLBA 501(b) safeguards rule

### Known Limitations

- Requires Entra ID P1 minimum (P2 for risk-based policies)
- Break-glass accounts must be manually excluded
- Report-only mode recommended before enabling
