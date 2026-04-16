# Changelog

All notable changes to the Cross-Tenant External Sharing Governance solution.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [1.0.1] - 2026-04-15

### Fixed

- Critical: CTA compliance validation now queries correct column fsi_unapprovedpartnercount (was fsi_unapprovedcount, which belongs to the isolation table)

## [1.0.0] - 2026-03-20

### Added

- **Three-layer governance model** — Power Platform Tenant Isolation (Layer 1), Entra Cross-Tenant Access (Layer 2), Copilot Studio Agent Shares (Layer 3)
- **Dataverse schema** — 5 tables:
  - `fsi_approvedexternaltenant` — Authoritative external tenant allow list
  - `fsi_externalsharefinding` — External sharing violations per agent
  - `fsi_tenantisolationrecord` — Daily tenant isolation audit snapshots
  - `fsi_entractarecord` — Weekly Entra CTA audit snapshots
  - `fsi_crosstenantcomplianceevent` — Immutable compliance event log (7-year LTR)
- **Python deployment scripts** — `create_ctsg_dataverse_schema.py`, `create_ctsg_environment_variables.py`, `create_ctsg_connection_references.py`, `deploy.py`
- **PowerShell governance scripts** — `Deploy-CrossTenantBaseline.ps1`, `Test-CrossTenantCompliance.ps1`
- **Power Automate flows (documentation-only, manual build):**
  - Flow 1: Validate-TenantIsolation-Daily
  - Flow 2: Detect-ExternalAgentShares-Daily (5-value guest detection method)
  - Flow 3: Audit-EntraCrossTenantSettings-Weekly
  - Flow 4: Execute-ExternalTenantOnboarding (dual-approval with Expired timeout)
  - Flow 5: Remediate-UnauthorizedExternalAccess (approval-gated)
  - Flow 6: Send-AnnualReviewReminders-Daily (90/30/overdue thresholds)
- **Two Managed Identities** — MI-CrossTenantReadOnly (Flows 1-3, 6), MI-CrossTenantReadWrite (Flows 4-5)
- **12 environment variables** including feature flag and CTA baseline configuration
- **Controls:** 1.1, 1.18, 2.1, 2.8, 3.1, 1.11
- **Regulatory alignment:** GLBA 501(b), OCC 2011-12, SOX 302/404, FINRA 4370/3110, NYDFS 23 NYCRR 500, FFIEC
