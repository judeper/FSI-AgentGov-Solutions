# Changelog

All notable changes to agent-knowledge-source-scanner will be documented in this file.

## [1.0.2] - April 2026

### Added
- `-ClientId` parameter for PnP.PowerShell 3.x tenant-specific app registration support
- Runtime detection of PnP.PowerShell 3.x with clear error when `-ClientId` is missing
- PnP.PowerShell 3.x prerequisites section in docs/prerequisites.md
- `Register-PnPEntraIDApp` setup instructions for tenant-specific app registration

### Changed
- `Get-PnPEntraIDGroupMember` used as primary cmdlet with `Get-PnPAzureADGroupMember` fallback for PnP 2.x backward compatibility
- `Connect-PnPOnline` now uses splatting to conditionally pass `-ClientId`
- Updated quick start examples to show both PnP 2.x and 3.x usage
- Updated troubleshooting guidance for PnP 3.x cmdlet renames and authentication changes

## [1.0.1] - April 2026

### Added
- Documentation suite: docs/prerequisites.md, docs/troubleshooting.md

## [1.0.0] - 2026-03-17

### Added

- `Get-KnowledgeSourceItemPermissions.ps1` — item-level permission scanner for agent knowledge source SharePoint libraries
- Risk scoring tailored to agent knowledge source context (CRITICAL, HIGH, MEDIUM, LOW)
- Sensitivity label cross-reference with configurable tier mapping
- Agent user scope comparison (security group or UPN list)
- CSV and JSON input support for multi-library scanning
- `item-scope-config.sample.json` configuration template
- Comprehensive README with architecture, prerequisites, and quick start
