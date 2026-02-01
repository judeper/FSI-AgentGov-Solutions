# Changelog

All notable changes to the Scope Drift Monitor.

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

*Scope Drift Monitor - FSI Agent Governance Framework*
