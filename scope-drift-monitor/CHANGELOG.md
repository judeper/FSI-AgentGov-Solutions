# Changelog

All notable changes to the Scope Drift Monitor.

---

## [Unreleased]

### Fixed

- Updated `Invoke-DriftScan.ps1` and `New-AgentBaseline.ps1` to parse the current Copilot audit payload shape (`CopilotEventData`, `AccessedResources`, `AISystemPlugin`, and agent identity variants) while retaining compatibility with legacy `EventData` records.
- Added managed identity-first token acquisition for Office 365 Management API and Dataverse calls; client-secret authentication is retained only as a legacy development fallback.
- Refreshed prerequisites and flow documentation for Microsoft Purview Power Platform activity logging, Copilot Studio audit-event behavior, and Microsoft Graph Audit Search API v1.0 status.
- Updated Microsoft Entra branding outside historical changelog entries.

---

## [1.2.0] - 2026-04-16

### Fixed

- **`Invoke-DriftScan.ps1`** — `Get-AuditEvents` no longer silently fails open when audit-content fetches throw. Each catch block now increments `$script:auditFetchErrors`, and the scanner exits with code 2 (inconclusive) when fetch errors occurred AND zero events were returned, preventing operators from interpreting silent failures as "no violations." (Council: agreed Opus + Goldeneye)
- **`New-AgentBaseline.ps1`** — Removed dead-code error handler at line ~163: the audit-subscription `Invoke-RestMethod` call was suppressing errors with `-ErrorAction SilentlyContinue`, which prevented the surrounding catch block from firing on real failures (403, 5xx). The catch is now reachable and inspects HTTP 400 correctly. (Opus M3)
- **`New-AgentBaseline.ps1`** — Duplicate-baseline pre-check now fails closed: when the existing-baseline query errors, the script exits non-zero rather than printing "Proceeding with creation." Added `-SkipDuplicateCheck` switch for explicit override. Prevents silent creation of duplicate active scopes that would cause non-deterministic scanner behavior. (Goldeneye M1)
- **`Test-AlertDelivery.ps1`** — `Send-EmailNotification` now establishes a Microsoft Graph context via `Connect-MgGraph -Scopes Mail.Send` before calling `Send-MgUserMail`, instead of failing with an opaque `AuthenticationRequired` error. Also re-connects when an existing context lacks `Mail.Send`, and verifies `Microsoft.Graph.Authentication` is installed. (Goldeneye M2)
- **`docs/prerequisites.md`** — Replaced the incorrect `Directory.Read.All` (Application) entry with `Mail.Send` (Delegated) under a new "Microsoft Graph Permissions" subsection scoped only to the `Test-AlertDelivery.ps1` email path; production scanner remains Office 365 Management API only.
- **`docs/baseline-configuration.md`** — Zone integer values in the `fsi_zone` choice tables corrected from 1/2/3 to 10001/10002/10003 to match `create_fsi_dataverse_schema.py` and `New-AgentBaseline.ps1` ValidateRange.
- **`README.md`** — "Related Controls" rewritten to match the canonical solutions-catalog mapping (1.14, 1.4, 1.5; previously listed 1.4/1.5/1.8). Reworded 1.4 and 1.5 as "supports monitoring/evidence" rather than enforcement to avoid overreach. GLBA citation upgraded to "GLBA Section 501(b)" per repository regulatory-language rules.

### Changed

- Council artifacts archived under `files/sdm/` (Opus + Goldeneye outputs).

---

## [1.1.2] - 2026-04-15

### Fixed

- Fixed Write-Output pipeline contamination in drift scan scripts
- Remediated prohibited FSI language, PnP 3.x compatibility, stale references

---

## [1.1.1] - 2026-07-15

### Removed

- **Exported Dataverse solution package** (`src/ScopeDriftMonitor/`) removed per repository content policy — solutions must not contain Power Platform runtime artifacts (flow JSON, connection references, environment variable exports)
- Updated Quick Start to reference manual build instructions instead of `pac solution pack` from `src/`

### Note

All flow logic remains fully documented in [Flow Configuration](docs/flow-configuration.md). Administrators should build flows manually in Power Automate designer following that guide.

---

## [1.1.0] - 2026-02-15

### Added

- **Power Automate Flows:**
  - `SDM-DriftDetector` - Scheduled drift detection using Office 365 Management API
  - `SDM-AlertDispatcher` - Teams adaptive card and email notifications on violations
  - `SDM-ExpansionProcessor` - Approval workflow for scope expansion requests
- **PowerShell Scripts:**
  - `New-AgentBaseline.ps1` - Auto-generate baselines from audit history (Office 365 Management API)
  - `Invoke-DriftScan.ps1` - Manual drift detection scan
  - `Test-AlertDelivery.ps1` - Test alert delivery configuration
- **Connection References:**
  - `fsi_cr_dataverse` - Dataverse connector
  - `fsi_cr_outlook` - Office 365 Outlook connector
  - `fsi_cr_teams` - Microsoft Teams connector
  - `fsi_cr_approvals` - Approvals connector
  - `fsi_cr_http_azuread` - HTTP with Azure AD for Management API
- **Environment Variables:**
  - `fsi_SDM_TenantId` - Azure AD tenant ID
  - `fsi_SDM_DataverseEnvironment` - Dataverse environment URL
  - `fsi_SDM_TeamsGroupId` - Teams team ID for alerts
  - `fsi_SDM_TeamsChannelId` - Teams channel ID for alerts
  - `fsi_SDM_SecurityTeamEmail` - Security team email
  - `fsi_SDM_DetectionWindowMinutes` - Detection lookback window in minutes
  - `fsi_SDM_ClientId` - Azure AD application client ID
  - `fsi_SDM_ClientSecret` - Azure AD application client secret
  - `fsi_SDM_ManagementApiEndpoint` - Office 365 Management API base URL (commercial, GCC High, or DoD)
  - `fsi_SDM_ActiveScopeStatus` - Active scope status code override for environments with custom option-set values
- **Documentation:**
  - `flow-configuration.md` - Flow setup and configuration guide
  - `troubleshooting.md` - Common issues and resolutions
  - `baseline-configuration.md` - Scope baseline setup guide
### Changed

- Updated `New-AgentBaseline.ps1` to use Office 365 Management API instead of Microsoft Graph
- Auto-generated baselines now go Active immediately (per governance decision)
- Enhanced README with complete deployment instructions

### Technical Decisions

- Office 365 Management API selected over Graph API (Graph auditLogs moved to beta April 2025)
- Graceful degradation when audit sources unavailable
- Dual alert delivery (Teams + email) for all violations
- Single-approver workflow with 7-day timeout for expansion requests
- Single-approver (`approvalType: "Basic"`) is an intentional v1.1 design choice for operational simplicity; regulated environments requiring separation of duties (FINRA, OCC, GDPR) should consider upgrading to `"Approve/Reject - Everyone must approve"` or multi-tier approval in a future release

---

## [1.0.0] - 2026-02-01

### Added

- Initial release of Scope Drift Monitor
- **Dataverse Schema:**
  - `fsi_agentscope` - Agent scope definitions
  - `fsi_scopeitem` - Individual scope items
  - `fsi_scopeviolation` - Drift violations
  - `fsi_expansionrequest` - Scope expansion requests
- **Security Roles:**
  - SDM Viewer - Read-only access
  - SDM Analyst - Violation and request management
  - SDM Admin - Full administrative access
- **PowerShell Scripts:**
  - `New-AgentBaseline.ps1` - Generate scope baseline from audit history
- **Detection Capabilities:**
  - Unauthorized connector access
  - Unauthorized SharePoint site access
  - Unauthorized Dataverse table access
  - Unauthorized external API calls
- **Documentation:**
  - Prerequisites and licensing
  - Dataverse schema definitions
  - Baseline configuration guide

### Regulatory Alignment

- GDPR Article 5(1)(c) - Data Minimization
- GLBA 501(b) - Customer Information Safeguards
- CCPA - Purpose Limitation

---

*Scope Drift Monitor v1.2.1 - FSI Agent Governance Framework*
