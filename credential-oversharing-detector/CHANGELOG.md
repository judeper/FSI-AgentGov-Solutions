# Credential Oversharing Detector — Changelog

All notable changes to this solution are documented here.

## [1.0.1] — 2026-04-15

### Fixed

- Critical: Scan persistence uses fsi_scanid instead of non-existent fsi_name
- Critical: Violation persistence uses fsi_violationid and adds required fsi_violationstatus
- Critical: Export uses correct column names (fsi_scanstartedat, fsi_agentsscanned, fsi_violationsfound)
- Zone filter in evidence export uses integer option set values instead of string literals

## [1.0.0] — 2026-04-01

### Added
- Dataverse schema with 5 tables: CredentialScan, CredentialViolation, CredentialPolicy, CredentialException, AgentConnectorScope
- 5 COD-specific option sets plus shared zone classification
- 11 environment variables for scan configuration, alerting, and exception management
- 4 connection references for Dataverse, Teams, Approvals, and Power Platform Admin
- `Invoke-CredentialScan.ps1` — main credential scope scanning script
- `Test-CredentialCompliance.ps1` — zone compliance validation orchestrator
- `Get-AgentConnectorScope.ps1` — per-agent connector scope extraction
- `Get-ExpectedCredentialPolicy.ps1` — zone-based policy lookup
- `Export-CredentialEvidence.ps1` — evidence export with SHA-256 integrity hash
- `Test-EvidenceIntegrity.ps1` — evidence hash verification
- Zone credential policy baseline template with Zone 1/2/3 thresholds
- Teams adaptive card template for scan alerts
- Prerequisites documentation
- Flow configuration guide with manual build instructions for 3 flows
- Troubleshooting guide
- Auto-generated Dataverse schema documentation

### Changed
- Upgraded from documentation-only placeholder (v0.1.0-preview) to full solution

### Notes
- This solution leverages the Microsoft "Enforce safe sharing by detecting credential oversharing" feature (public preview April 2026)
- Organizations should verify feature availability in their tenant before production deployment
- See [Microsoft release plan](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/microsoft-copilot-studio/enforce-safe-sharing-detecting-credential-oversharing) for current status

## [0.1.0-preview] — 2026-03-01

### Added
- Initial documentation-only placeholder
- Namespace reservation for credential oversharing governance
- Boundary documentation with existing solutions
- Microsoft feature status tracking
