# Changelog

All notable changes to the Content Moderation Monitor.

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
