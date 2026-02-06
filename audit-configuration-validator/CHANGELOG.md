# Changelog

All notable changes to the Audit Configuration Validator solution will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Phase 3 - Power Automate Integration (Planned)
- Power Automate flow for scheduled tenant validation
- Power Automate flow for environment validation
- Dataverse integration for validation history storage
- Grace period query and alerting

### Phase 4 - Alerting & Reporting (Planned)
- Teams notification for validation failures
- Email alerts for grace period expirations
- Dashboard integration (v9 milestone)
- Quarterly compliance reports

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
- **v0.2.0** - Infrastructure deployment and environment validation capabilities
- **Next** - Power Automate integration for scheduled automation (v0.3.0)

### Milestone Roadmap
- v0.1.0 - Core PowerShell validators (tenant-level) ✓
- v0.2.0 - Python infrastructure and Dataverse schema (in progress)
- v0.3.0 - Power Automate flows (scheduled tenant + environment validation)
- v0.4.0 - Alerting and reporting (Teams, Email, Dashboard prep)
- v1.0.0 - Production-ready with full automation + alerting
