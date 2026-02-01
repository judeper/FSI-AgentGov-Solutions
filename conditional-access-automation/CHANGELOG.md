# Changelog

All notable changes to the Conditional Access Automation solution are documented here.

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
