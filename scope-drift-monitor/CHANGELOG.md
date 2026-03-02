# Changelog

All notable changes to the Scope Drift Monitor.

---

## [1.1.0] - February 2026

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
- **Solution Package:**
  - Unpacked solution source in `src/ScopeDriftMonitor/`
  - Support for `pac solution pack` workflow

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

## [1.0.0] - February 2026

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

*Scope Drift Monitor v1.1.0 - FSI Agent Governance Framework*
