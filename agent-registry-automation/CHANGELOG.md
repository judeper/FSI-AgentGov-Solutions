# Changelog

All notable changes to Agent Registry Automation are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [1.0.1] - 2026-04-16

### Updated

- Product name: "Azure AD" / "HTTP with Azure AD" → "Microsoft Entra ID" / "HTTP with Microsoft Entra ID" across Python scripts

### Added

- Created `.ralph-config.json` with domain facts from council review

---

## [1.0.0] - March 2026

### Added

- **Dataverse Schema** — 4 tables for agent lifecycle governance:
  - `fsi_agentinventory` — Master agent registry with alternate key on (`fsi_agentid`, `fsi_environmentid`)
  - `fsi_registrationrequest` — Registration request tracking with SLA and escalation
  - `fsi_agentcomplianceevent` — Immutable compliance event log (LTR-enabled)
  - `fsi_ownershipaudit` — Ownership change audit trail
- **Python Deployment Scripts:**
  - `create_dataverse_schema.py` — Schema deployment with option sets and alternate keys
  - `create_environment_variables.py` — 7 environment variables for flow configuration
  - `create_connection_references.py` — 4 connection references for Power Automate flows
  - `deploy.py` — Orchestrator with `--dry-run`, `--tables-only`, `--vars-only`, `--refs-only`
- **PowerShell Governance Scripts:**
  - `Deploy-AgentRegistry-Baseline.ps1` — Baseline inventory export (Managed Identity auth)
  - `Validate-AgentRegistry-Compliance.ps1` — Compliance validation with examiner reporting
- **Power Automate Flows** (documentation-only, manual build):
  - Flow 1: Discover-UnregisteredAgents-Daily — daily Bots API scan across all environments
  - Flow 2: Enforce-RegistrationApproval-Gate — Teams approval with SLA tracking and escalation
  - Flow 3: Sync-EntraAgentRegistry — Entra Agent Registry sync (feature-flagged, disabled by default)
  - Flow 4: Detect-OrphanedAgents-Weekly — orphan detection for departed or inactive owners
- **Documentation:**
  - Dataverse schema reference (`docs/dataverse-schema.md`)
  - Flow configuration with manual build instructions (`docs/flow-configuration.md`)
  - Prerequisites guide (`docs/prerequisites.md`)
  - Troubleshooting guide (`docs/troubleshooting.md`)
  - Delivery checklist (`DELIVERY-CHECKLIST.md`)
  - Sample configuration template (`templates/agent-registry-config.sample.json`)
- Supports Controls 1.2 (primary), 1.7, 2.1, 2.13 (secondary)

### Regulatory Alignment

- FINRA Rule 4511 — Books and records for AI agent systems
- SEC Rule 17a-3/4 — Immutable retention via Dataverse LTR
- OCC Bulletin 2011-12 — Model inventory with ownership and risk classification
- Fed SR 11-7 — Comprehensive inventory with zone-based risk classification
- GLBA 501(b) — Safeguards with owner validation and orphan detection

### Technical Decisions

- Bots API (`2022-03-01-preview`) selected for agent discovery — only available API for bot enumeration across environments
- Entra Agent Registry sync is feature-flagged off by default pending API GA
- Alternate key on (`fsi_agentid`, `fsi_environmentid`) enables upsert-based idempotent discovery
- `fsi_agentcomplianceevent` designed for Dataverse Long-Term Retention (7-year SEC 17a-3/4 support)
- Office 365 Users connector used for time zone lookup in SLA calculations; configurable fallback for DLP-restricted environments

---

*Agent Registry Automation v1.0.0 — FSI Agent Governance Framework*
