# Changelog

All notable changes to the Conditional Access Automation solution are documented here.

## [1.1.0] - 2026-02-10

### Added
- CAAClient PowerShell module with 8 Dataverse functions (Connect, Read, Write)
- Azure Automation runbook (Start-CAAValidationRunbook.ps1) for unattended daily execution
- Power Automate daily compliance scan flow (caa-daily-compliance-flow.json)
- ELM provisioning hook flow (caa-provisioning-hook-flow.json)
- Teams adaptive card alert template (adaptive-card-caa-alert.json)
- Dataverse schema: 3 tables (Baseline, ValidationHistory, Violation)
- 7 environment variables with fsi_CAA_* prefix
- 4 connection references with fsi_cr_* naming
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
- 8 Conditional Access policy templates for AI workloads
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
- `Export-PolicyEvidence.ps1` - Compliance evidence

### Security Alignment

- Zero Trust architecture (verify explicitly)
- NIST 800-53 AC-2, IA-2 controls
- SOX 404 IT general controls
- GLBA 501(b) safeguards rule

### Known Limitations

- Requires Entra ID P1 minimum (P2 for risk-based policies)
- Break-glass accounts must be manually excluded
- Report-only mode recommended before enabling
