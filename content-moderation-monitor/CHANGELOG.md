# Changelog

All notable changes to the Content Moderation Monitor.

## [1.0.1] - 2026-02-15

### Fixed
- Corrected primary control reference from 1.14 to 1.27 (AI Agent Content Moderation Enforcement) in README.md and SOLUTION-DOCUMENTATION.md
- Fixed Related Controls URL slug to `1.27-ai-agent-content-moderation-enforcement/`
- Added explicit `src/` path prefix to flow file reference in DELIVERY-CHECKLIST.md
- Fixed FSI language compliance: "Ensure consistent" → "Help ensure consistent" in SOLUTION-DOCUMENTATION.md and DELIVERY-CHECKLIST.md

### Removed
- Empty `flows/` directory (flow file lives in `src/moderation-validation-flow.json`)

### Added
- `src/dataverse/README.md` explaining placeholder subdirectories and programmatic schema deployment

## [1.0.0] - 2026-02-10

### Added — Phase 4: Evidence Export & Framework Integration
- `Export-ContentModerationEvidence.ps1` — SHA-256 integrity-hashed compliance evidence export with zone filtering, date range, baseline inclusion, and interactive/service principal authentication
- `Get-CMMValidationResults.ps1` — Dataverse query helper for validation history and violations with OData pagination, zone filtering, and RunId support
- `Test-EvidenceIntegrity.ps1` — Evidence integrity verification utility comparing computed SHA-256 against companion hash file
- Control 1.8 tip admonition linking to Content Moderation Governance Monitor solution
- solutions-index.md catalog entry with components, regulatory alignment, and repository link
- `docs/SCHEMA.md` — Complete Dataverse schema reference (3 tables, option sets, environment variables, connection references, entity relationship diagram)
- `docs/EVIDENCE_EXPORT.md` — Step-by-step evidence export guide with interactive, service principal, zone filter, and baseline inclusion examples
- `docs/TROUBLESHOOTING.md` — Comprehensive troubleshooting guide covering deployment, authentication, validation, drift detection, evidence export, and Power Automate flow issues
- Updated `docs/PREREQUISITES.md` with MSAL.PS module requirement for evidence export

### Changed
- README.md updated to v1.0.0 with evidence export features, Quick Start steps 5-6, expanded solution components tree, and documentation links section

## [0.3.0] - 2026-02-10

### Added
- Start-ModerationValidationRunbook.ps1 — Azure Automation runbook wrapper for non-interactive daily content moderation validation with certificate-based auth, per-agent drift detection via batch baseline query, and structured JSON output
- Invoke-ModerationBaselineCapture.ps1 — Operator-initiated per-agent baseline capture writing moderation levels to Dataverse with active baseline management and zone/environment/agent filtering
- adaptive-card-moderation-alert.json — Teams adaptive card template for content moderation violation and drift alerts with per-agent severity classification and regulatory context
- moderation-validation-flow.json — Power Automate cloud flow for daily scheduled moderation validation, immutable Dataverse history persistence, and conditional Teams/email alerting (Critical→Teams+email, High→email)
- FLOW_SETUP.md — Step-by-step guide for flow import, variable configuration, connection reference binding, baseline capture workflow, and troubleshooting

### Changed
- Save-CMMBaseline in CMMClient.psm1 completed with active baseline deactivation before new baseline write (single active baseline per agent)
- Get-ModerationBaseline in CMMClient.psm1 enhanced with -AgentId and -ActiveOnly parameters for per-agent drift detection and batch baseline queries
- CMMClient.psm1 version bumped to 0.3.0

## [0.2.0] - 2026-02-10

### Added — Phase 2: Dataverse Infrastructure

#### Python Deployment Scripts
- **cmm_client.py** — CMMClient Dataverse Web API client with MSAL auth (interactive + service principal)
- **create_dataverse_schema.py** — Three-table schema deployment (ModerationBaseline, ModerationValidationHistory, ModerationViolation)
- **create_environment_variables.py** — Seven `fsi_CMM_*` operational parameters
- **create_connection_references.py** — Three Power Automate connection references (Dataverse, Office 365, Teams)
- **deploy.py** — Full deployment orchestrator with selective/dry-run modes (`--tables-only`, `--vars-only`, `--refs-only`)
- **requirements.txt** — Python dependencies (msal, requests)

#### Dataverse Integration in PowerShell
- `-DataverseToken` parameter on `Test-ContentModerationCompliance` for pre-obtained authentication tokens
- `-PersistResults` switch for writing validation results to Dataverse
- Operational parameter reading from `fsi_CMM_*` environment variables (GracePeriodHours, IncludeDrafts, IncludeSandbox)
- RunId correlation across validation history and violation records
- `EnvironmentId` added to `Compare-ModerationCompliance` output

### Changed
- `Test-ContentModerationCompliance` reads GracePeriodHours, IncludeDrafts, IncludeSandbox from Dataverse when connected
- Standalone mode (no `-DataverseUrl`) remains unchanged — no regression
- CMMClient.psm1 bumped to v0.2.0

## [0.1.0] - 2026-02-09

### Added — Phase 1 Plan 01-01: Solution scaffold and private helpers

#### Solution Structure
- Solution folder structure following Tier 2 pattern
- `moderation-baseline.json` — Zone-to-moderation-level requirements reference

#### Private Helpers
- **CMMClient.psm1** — Dataverse client module (10 exported functions)
  - `Connect-CMMDataverse`, `Get-CMMConnection` — Connection management
  - `Get-CMMEnvironmentVariable` — Environment variable lookup (`CMM_` prefix)
  - `Get-ModerationBaseline` — Queries `fsi_moderationbaseline` table
  - `Write-ModerationValidationHistory` — Writes to `fsi_moderationvalidationhistory`
  - `Write-ModerationViolation` — Writes to `fsi_moderationviolations`
  - `Get-AgentBots` — Queries `bot` table with pagination support
  - `Get-BotModerationLevel` — Extracts and normalizes moderation level from bot config
  - `Save-CMMBaseline`, `Get-CMMLastValidation` — Phase 3 stubs

- **Connect-EnvironmentDataverse.ps1** — Per-environment Dataverse authentication
  - Token caching per DataverseUrl
  - Service principal support (PSCredential)
  - Interactive fallback via Az.Accounts
  - Clear error messages with remediation guidance

- **Get-ZoneClassification.ps1** — Zone lookup (ELM → naming convention → Unknown)
- **Get-ExpectedModerationLevel.ps1** — Zone-to-moderation compliance check with severity
- **Test-ParameterValidation.ps1** — Parameter validators including `Test-ModerationLevel`

#### Stubs
- `Get-AgentModerationSettings.ps1` — Stub for Plan 01-02
- `Compare-ModerationCompliance.ps1` — Stub for Plan 01-02
- `Test-ContentModerationCompliance.ps1` — Stub for Plan 01-03

#### Documentation
- `README.md` — Solution overview with zone requirements and severity matrix
- `CHANGELOG.md` — This file
- `docs/PREREQUISITES.md` — Module and permission requirements
- `docs/SCHEMA.md` — Stub for Dataverse schema documentation
- `docs/EVIDENCE_EXPORT.md` — Stub for evidence export documentation
- `docs/TROUBLESHOOTING.md` — Stub for troubleshooting guide
