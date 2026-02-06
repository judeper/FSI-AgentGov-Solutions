# Changelog

All notable changes to the Audit Configuration Validator solution will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

No planned changes. Solution is feature-complete for v4 milestone.

## [1.0.0] - 2026-02-06

### Added - Phase 4: Evidence Export & Framework Integration

#### Evidence Export
- **Export-AuditValidationEvidence.ps1** - Main evidence export script
  - Supports Tenant and Environment scope
  - Date range filtering with -FromDate and -ToDate parameters
  - JSON output with -Depth 10 (prevents nested object truncation)
  - SHA-256 companion hash files in standard format
  - Interactive and service principal authentication modes

- **Get-ValidationResults.ps1** (private) - Dataverse query helper
  - OData filter construction for scope, date range, RunId
  - Pagination handling for large result sets

- **Test-EvidenceIntegrity.ps1** - Hash verification utility
  - SHA-256 hash comparison against companion .sha256 files
  - Batch verification support via pipeline
  - Quiet mode for automation

#### Documentation
- Evidence export guide (docs/evidence-export-guide.md)
- Updated README with complete Phase 4 content
- Framework integration (Control 1.7 tip admonition, solutions-index.md entry)

## [0.3.0] - 2026-02-06

### Added - Phase 3: Automated Orchestration & Alerting

#### Azure Automation Runbooks
- **Start-TenantValidationRunbook.ps1** - Azure Automation wrapper for tenant validation
  - Authenticates using certificate-based service principal
  - Runs all three tenant validators (UAL, mailbox, Purview)
  - Writes results to Dataverse
  - Returns structured JSON for Power Automate consumption

- **Start-EnvironmentValidationRunbook.ps1** - Azure Automation wrapper for environment validation
  - Discovers and validates all registered environments
  - Per-environment audit and retention validation
  - Writes results to Dataverse
  - Returns per-environment JSON results

#### Drift Detection
- **Compare-ValidationBaseline.ps1** (private) - Configuration drift detection
  - Compares current validation against last known baseline
  - Numeric severity comparison (Passed=1, Error=5)
  - Per-validator drift for tenant, per-environment for environments
  - First run treats non-Passed as drift (no baseline suppression)

#### Power Automate Flows
- **tenant-validation-flow.json** - Daily tenant validation at 6 AM UTC
- **environment-validation-flow.json** - Daily environment validation at 7 AM UTC
- Severity-based alert routing (Failed/Error → Teams + email, Warning → email only)
- Scope Try-Catch error handling pattern

#### Alerting
- **adaptive-card-tenant-alert.json** - Teams card for tenant drift alerts
- **adaptive-card-environment-alert.json** - Teams card for environment drift alerts
- Email alerts to compliance distribution list

#### Documentation
- Flow setup guide (docs/FLOW_SETUP.md)

## [0.2.0] - 2026-02-06

### Added - Phase 2: Infrastructure & Environment Validation

#### Dataverse Infrastructure
- **acv_client.py** - Dataverse Web API client with MSAL authentication
  - Interactive browser auth via PublicClientApplication
  - Service Principal auth via ConfidentialClientApplication
  - Token caching with acquire_token_silent
  - Retry logic with HTTPAdapter (3 retries, exponential backoff)
  - Dry-run mode for preview without changes
  - Idempotent helper methods (create_table, create_option_set, check_table_exists)

- **create_dataverse_schema.py** - Table and option set creation
  - 5 global option sets: fsi_acv_severity, fsi_acv_scope, fsi_acv_zone, fsi_acv_envstatus, fsi_acv_environmenttype
  - fsi_auditvalidationhistory table (organization-owned, 12 columns)
  - fsi_environmentregistry table (organization-owned, 10 columns)
  - Idempotent deployment (checks existing schema before creation)

- **create_environment_variables.py** - Configurable zone thresholds
  - fsi_ACV_Zone1RetentionDays (default: 180)
  - fsi_ACV_Zone2RetentionDays (default: 365)
  - fsi_ACV_Zone3RetentionDays (default: 730)
  - fsi_ACV_GracePeriodHours (default: 24)
  - fsi_ACV_CanaryWaitMinutes (default: 5)

- **create_connection_references.py** - Solution connector definitions
  - fsi_cr_dataverse_auditvalidation (Dataverse connector)
  - fsi_cr_office365_auditvalidation (Office 365 connector)

- **deploy.py** - Orchestrator for all Dataverse provisioning
  - Full deployment (schema + env vars + connection refs)
  - Selective deployment flags (--tables-only, --vars-only, --refs-only)
  - Dry-run preview mode (--dry-run)
  - Interactive and Service Principal auth support
  - Idempotent execution with clear status reporting

#### Documentation
- README.md with solution overview, prerequisites, quick start, zone requirements
- Solution folder structure (docs/, src/, scripts/)
- requirements.txt with Python dependencies (msal, requests, azure-identity, azure-keyvault-secrets)

### Changed
- Adopted Tier 2 solution pattern from environment-lifecycle-management
- All schema names use fsi_ prefix for consistency
- Organization-owned tables for immutability (security roles must remove Write/Delete post-deployment)

## [0.1.0] - 2026-02-06

### Added - Phase 1: Core Validation Scripts

#### PowerShell Validators
- **Test-UnifiedAuditLog.ps1** - Tenant-wide Unified Audit Log validation
  - Checks audit enablement via Get-AdminAuditLogConfig
  - Canary event validation with CustomAttribute15 (5-minute default wait)
  - 24-hour grace period for newly enabled audit
  - Zone-specific retention validation

- **Test-MailboxAudit.ps1** - Mailbox-level audit validation
  - Organization-wide mailbox audit defaults
  - Per-mailbox audit configuration
  - AuditDisabled inverted logic handling (AuditDisabled=$false means enabled)
  - Gap detection with configurable sample size

- **Test-PurviewRetention.ps1** - Microsoft Purview retention policy validation
  - Exchange mailbox retention policies
  - Catch-all policy detection (empty RecordTypes)
  - Zone-specific retention thresholds
  - Gap analysis with severity ratings (Critical, High, Warning)

#### Helper Functions
- **Connect-AuditServices.ps1** - Service connection management
  - Exchange Online PowerShell (for Get-AdminAuditLogConfig)
  - Security & Compliance PowerShell (for Search-UnifiedAuditLog)
  - Purview Compliance PowerShell (for retention policies)
  - Idempotent connection handling (skip if already connected)

- **New-CanaryEvent.ps1** - Audit event generation
  - Creates verifiable audit events using CustomAttribute15
  - Configurable wait time for propagation (default: 5 minutes)
  - Returns event metadata for validation correlation

#### Orchestrator
- **Invoke-TenantAuditValidation.ps1** - Main entry point
  - Isolated validator execution (try-catch per validator)
  - Overall status computation (Error/Failed > Warning/GracePeriod > Passed)
  - Required Zone parameter (forces explicit zone declaration)
  - Optional JSON output via -OutputPath parameter
  - Supports both manual and automation scenarios

### Decisions
- Exchange Online PowerShell for Get-AdminAuditLogConfig (Security & Compliance version returns false positives)
- Dual validation strategy: cmdlet checks + canary event retrieval
- CustomAttribute15 for canary events (auditable, non-disruptive)
- 24-hour grace period for newly-enabled audit (prevents false warnings)
- 5-minute default canary wait (configurable for speed/accuracy balance)
- Zone-specific retention thresholds: Zone 1 = 180d, Zone 2 = 365d, Zone 3 = 730d
- Default 90-day retention assumption when no custom Purview policies exist
- Catch-all policy detection (empty RecordTypes covers all record types)

## Version Notes

### Current Focus
- **v1.0.0** - Feature-complete with evidence export and framework integration

### Milestone Roadmap
- v0.1.0 - Core PowerShell validators (tenant-level) ✓
- v0.2.0 - Python infrastructure and Dataverse schema ✓
- v0.3.0 - Power Automate flows (scheduled tenant + environment validation) ✓
- v1.0.0 - Evidence export, integrity verification, framework integration ✓
