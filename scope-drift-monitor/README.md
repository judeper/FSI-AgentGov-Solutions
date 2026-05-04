# Scope Drift Monitor

> **Status:** Completed (v1.2.1)

Automated detection of AI agent data access beyond declared operational scope, supporting GDPR data minimization and FSI data governance requirements.

## Overview

The Scope Drift Monitor tracks what data sources, connectors, and content each AI agent accesses and alerts when access extends beyond the agent's declared scope. This supports the principle of data minimization—agents should only access data necessary for their stated purpose.

## Features

| Feature | Description |
|---------|-------------|
| **Scope Baseline** | Define allowed connectors, sites, tables per agent |
| **Real-Time Detection** | Monitor access within 15 minutes of occurrence |
| **Drift Alerts** | Immediate notification when scope exceeded |
| **Expansion Workflow** | Request and approve scope changes |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Scope Drift Monitor                           │
├─────────────────────────────────────────────────────────────────┤
│  Baseline Mgr  │  Drift Detector  │  Alert Engine  │  Expansion │
└────────────────┴──────────────────┴────────────────┴────────────┘
                              ▲
                              │ Analysis
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Dataverse (Scope Registry)                    │
├────────────────┬────────────────┬────────────────┬──────────────┤
│ Agent Scope    │ Scope Items    │ Drift          │ Expansion    │
│ Definition     │ (per-resource) │ Violation      │ Request      │
└────────────────┴────────────────┴────────────────┴──────────────┘
                              ▲
                              │ Data Sources
                              │
┌─────────────────────────────────────────────────────────────────┐
│ Purview Audit / O365 Mgmt API (CopilotInteraction, RecordType 261) │
│ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │
│ Current payload: CopilotEventData.AccessedResources + AgentId metadata │
└─────────────────────────────────────────────────────────────────┘
```

## Scope Components

Each agent scope record (`fsi_agentscope`) defines allowed resources as JSON arrays:

| Component | Field | Description |
|-----------|-------|-------------|
| **Connectors** | `fsi_allowedconnectors` | JSON array of permitted connector types |
| **SharePoint Sites** | `fsi_allowedsites` | JSON array of allowed site URLs |
| **Dataverse Tables** | `fsi_allowedtables` | JSON array of allowed table logical names |
| **External APIs** | `fsi_allowedapis` | JSON array of approved API endpoint URLs |

> **Note:** The detection flows compare accessed resources against these aggregate allowed-list columns. Sub-resource controls (blocked connectors, row-level scope, column restrictions, HTTP method filtering) are not currently implemented.

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows |
| **Dataverse capacity** | Scope and violation storage |
| **Microsoft 365 E5** or **E5 Compliance** | Unified Audit Log access |
| ~~**Defender for Cloud Apps**~~ | ~~CloudAppEvents access~~ *(not currently used — future roadmap)* |

### Permissions

| Role | Required For |
|------|--------------|
| **Purview Compliance Admin** | Audit log queries |
| ~~**Security Reader**~~ | ~~Defender CloudAppEvents~~ *(not currently used — future roadmap)* |
| **System Administrator** | Dataverse table creation |

## Quick Start

### 1. Create Dataverse Schema and Flows

Build the solution components manually in your target environment:

1. Create the Dataverse tables manually per the [Dataverse Schema](docs/dataverse-schema.md) documentation.
2. Build the Power Automate flows manually following [Flow Configuration](docs/flow-configuration.md)

### 2. Configure Environment Variables

After import, configure these environment variables in Power Apps:

| Variable | Value |
|----------|-------|
| `fsi_SDM_TenantId` | Your Microsoft Entra ID tenant ID |
| `fsi_SDM_DataverseEnvironment` | `https://your-org.crm.dynamics.com` |
| `fsi_SDM_TeamsGroupId` | Teams team ID for alerts |
| `fsi_SDM_TeamsChannelId` | Teams channel ID for alerts |
| `fsi_SDM_SecurityTeamEmail` | Security team email for approvals |
| `fsi_SDM_ClientId` | Legacy dev-only Microsoft Entra ID application client ID for local script fallback; flows use connection references |
| `fsi_SDM_ClientSecret` | Legacy dev-only Microsoft Entra ID application secret for local script fallback — use managed identity for Azure-hosted production automation |
| `fsi_SDM_DetectionWindowMinutes` | Detection lookback window in minutes (default: 15) |
| `fsi_SDM_ActiveScopeStatus` | Option-set value for Active status on fsi_agentscope (default: 10002) |
| `fsi_SDM_ManagementApiEndpoint` | Office 365 Management API base URL (default: `https://manage.office.com`; use `https://manage.office365.us` for GCC High, `https://manage.office.eaglex.ic.gov` for GCC IC, `https://manage.protection.outlook.com` for DoD) |

### 3. Configure Connection References

Connect each connection reference to an appropriate connection:

- `fsi_cr_dataverse` - Dataverse connection
- `fsi_cr_outlook` - Office 365 Outlook connection
- `fsi_cr_teams` - Microsoft Teams connection
- `fsi_cr_approvals` - Approvals connection
- `fsi_cr_http_azuread` - HTTP with Microsoft Entra ID (Office 365 Management APIs)

### 4. Capture Agent Baselines

```powershell
# Auto-generate baseline from audit history
.\scripts\New-AgentBaseline.ps1 -AgentId "guid" -Environment "https://your-org.crm.dynamics.com" -EnvironmentId "env-guid" -OwnerId "user-guid"
```

### 5. Turn On Flows

1. Navigate to **Power Automate** > **Solutions** > **Scope Drift Monitor**
2. Turn on each flow:
   - SDM-DriftDetector
   - SDM-AlertDispatcher
   - SDM-ExpansionProcessor

### 6. Run Initial Scan (Optional)

```powershell
# Manual drift scan to verify configuration
.\scripts\Invoke-DriftScan.ps1 -Environment "https://your-org.crm.dynamics.com"

# Test alert delivery
.\scripts\Test-AlertDelivery.ps1 -Channel Both -TeamsWebhook "https://your-webhook-url" -EmailRecipient "security@contoso.com" -FromEmail "alerts@contoso.com"
```

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Licensing and permission requirements |
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions |
| [Baseline Configuration](docs/baseline-configuration.md) | Setting up agent scopes |
| [Flow Configuration](docs/flow-configuration.md) | Detection flow setup |
| [Troubleshooting](docs/troubleshooting.md) | Common issues |

## Detection Logic

### What Triggers a Drift Violation

| Trigger | Severity | Example |
|---------|----------|---------|
| **New Connector** | High | Agent uses SQL connector not in scope |
| **New SharePoint Site** | Medium | Agent accesses HR site outside scope |
| **New Dataverse Table** | Medium | Agent queries Contacts when only Accounts allowed |
| **New External API** | High | Agent calls undeclared third-party API |
| **Expired Scope Item** | Medium | A scope entry's validity period has lapsed |
| **No Baseline Defined** | High | Agent has no baseline record in Dataverse |

### Detection Sources

| Source | Data Captured | Status |
|--------|---------------|--------|
| **Microsoft Purview Audit / Office 365 Management API** | CopilotInteraction events (RecordType 261) with `CopilotEventData.AccessedResources`, `AISystemPlugin`, and agent identity metadata | **Active** |
| **CloudAppEvents** | Defender detections including shadow IT | *Future roadmap* |
| **SharePoint Audit** | Site/library access events | *Future roadmap* |
| **Dataverse Audit** | Table read/write operations | *Future roadmap* |

> **Note:** The SDM-DriftDetector flow currently queries only the Office 365 Management API (`Audit.General` content type filtered to RecordType 261 — CopilotInteraction). Microsoft Graph `/security/auditLog/queries` is available in v1.0 for Purview Audit Search, but this solution remains on the Office 365 Management API pending a future collector migration and national-cloud validation. CloudAppEvents, SharePoint Audit, Dataverse Audit, Microsoft Entra sign-in logs, and Application Insights correlations are supplemental signals planned for future releases.

### Detection Frequency

| Mode | Frequency | Description |
|------|-----------|-------------|
| **Scheduled** | Every 15 minutes | All agents across all zones are checked on each recurrence cycle |

> **Note:** The SDM-DriftDetector flow runs on a single 15-minute recurrence for all zones. Zone-based frequency differentiation is not currently implemented.

## Scope Expansion Workflow

When drift is detected, users can request scope expansion:

```
Drift Detected → Alert Sent → Expansion Requested
       ↓
Security Team Review → Approved/Denied
       ↓
If Approved: Update Agent Scope → Close Violation
If Denied: Remediate Access → Close Violation
```

### Approval Requirements

| Scope Type | Approvers |
|------------|-----------|
| New Connector | Security Team |
| New SharePoint Site | Security Team |
| New Dataverse Table | Security Team |
| New External API | Security Team |

> **Note:** All expansion requests are currently routed to the security team (`fsi_SDM_SecurityTeamEmail`) for approval. Dual-approval workflows (e.g., Data Owner + Security) are not yet implemented. The schema includes `fsi_dataownerapproval` and `fsi_dataownerapprovedby` fields for future use.

## Regulatory Alignment

### GDPR Article 5(1)(c)

> Personal data shall be adequate, relevant and limited to what is necessary.

**Coverage:** Scope definitions help limit agent access to declared data sources.

### GLBA Section 501(b)

> Safeguards to protect the security and confidentiality of customer records.

**Coverage:** Drift detection identifies unauthorized access to customer data.

### CCPA Purpose Limitation

> Data collected for specified purposes cannot be used for incompatible purposes.

**Coverage:** Scope monitoring supports purpose-limited data access requirements.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.14 - Data Loss Prevention](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.14-data-loss-prevention.md) | Detective scope-drift monitoring complements preventive DLP policy enforcement |
| [1.4 - Advanced Connector Policies](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.4-advanced-connector-policies-for-copilot-studio.md) | Provides monitoring evidence for connector classification (this solution does not block connectors) |
| [1.5 - DLP and Sensitivity Labels](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.5-data-loss-prevention-dlp-and-sensitivity-labels.md) | Provides monitoring evidence for sensitive-data access (row-level / column-level enforcement is not implemented) |

## Known Limitations

### Microsoft Purview Sensitivity Labels (2026 Wave 1)

Microsoft is introducing [sensitivity label visibility in Copilot Studio](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/power-platform-governance-administration/view-sensitivity-labels-copilot-studio) (GA June 2026). This feature enables Purview autolabeling at the Dataverse column level, with labels surfaced in Copilot Studio knowledge source selection and agent response citations.

**Relationship to this solution:** Purview sensitivity labels provide **classification and visibility** — they label data and surface those labels to makers and users. The Scope Drift Monitor provides **detection and audit workflow support** — it detects when agents access resources beyond their declared operational scope and triggers remediation workflows. As Purview labels become available, organizations can use label metadata to enrich scope baselines (e.g., auto-flag agents accessing columns labeled "Highly Confidential" that are outside declared scope). The two capabilities are complementary.

- **Detection telemetry not persisted:** The `Compose_Detection_Summary` action builds operational telemetry (events processed, violations created, source availability) each cycle but does not persist it to Dataverse. Detection metrics are only available through Power Automate's 28-day run history. Organizations with FSI audit retention requirements should export flow run data to a long-term store (see [Flow Configuration > Known Limitations](docs/flow-configuration.md)).
- **Scope item records not auto-provisioned:** The `New-AgentBaseline.ps1` script populates aggregate `fsi_agentscope` JSON arrays (allowed connectors, sites, tables, APIs) but does not create individual `fsi_scopeitem` rows. The `Check_Expired_Scope_Items` scope in SDM-DriftDetector queries `fsi_scopeitem` for expired entries, so expiration-based detection requires manual Dataverse record creation or a custom provisioning script.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.2.1 | May 2026 | Microsoft Learn 2026-Q2 refresh: Copilot audit schema parsing, managed identity-first scripts, and updated Purview/Graph guidance |
| 1.1.2 | April 2026 | Fixed Write-Output pipeline contamination, prohibited language, PnP 3.x compatibility |
| 1.1.1 | July 2026 | Removed exported Dataverse solution package per content policy |
| 1.1.0 | February 2026 | Production release with flows, scripts, and full documentation |
| 1.0.0 | February 2026 | Initial schema and concept |

## Support

For issues and feature requests, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - Scope Drift Monitor v1.2.1*
