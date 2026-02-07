# Session Security Configurator - Changelog

All notable changes to the Session Security Configurator solution are documented here.

## [1.0.0] - Unreleased

### Added

- Phase 1: PowerShell Core - Authentication context lifecycle, step-up policy deployment, zone validation
  - Private helper scripts: Connect-GraphSession, Test-BreakGlassExclusion, Compare-SessionBaseline
  - Authentication context definitions (c1-c5) for FSI-AgentGov zones
  - Step-up policy templates for Zone 1 (8h), Zone 2 (4h + passwordless), Zone 3 (1h + phishing-resistant)
  - Session baseline templates for zone compliance validation
