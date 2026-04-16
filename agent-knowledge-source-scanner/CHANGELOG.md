# Changelog

All notable changes to agent-knowledge-source-scanner will be documented in this file.

## [1.0.2] - 2026-04-16

### Fixed

- Updated `Get-PnPAzureADGroupMember` → `Get-PnPEntraIDGroupMember` (current PnP cmdlet name)
- Updated PnP.PowerShell minimum version from 2.5.0 to 3.0.0 and PowerShell from 7.0 to 7.2
- Updated cmdlet references in prerequisites.md and troubleshooting.md
- Updated template version from 1.0.0 to 1.0.2

### Added

- Regulatory Context section in README.md with GLBA 501(b), FINRA 4511, SEC 17a-3/4 citations
- WORM storage guidance for scan evidence retention
- Created `.ralph-config.json` with domain facts from council review

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
