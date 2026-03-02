# Scope Drift Monitor

> **Status:** Completed (v1.1.0)

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
│ Agent Scope    │ Access Log     │ Drift          │ Expansion    │
│ Definition     │ (aggregated)   │ Violation      │ Request      │
└────────────────┴────────────────┴────────────────┴──────────────┘
                              ▲
                              │ Data Sources
                              │
┌─────────────┬───────────────┬───────────────┬───────────────────┐
│ Unified     │ Defender      │ SharePoint    │ Dataverse         │
│ Audit Log   │ CloudAppEvents│ Audit         │ Audit             │
└─────────────┴───────────────┴───────────────┴───────────────────┘
```

## Scope Components

### Connectors

| Component | Description |
|-----------|-------------|
| **Allowed Connectors** | List of permitted connector types |
| **Blocked Connectors** | Explicitly denied connectors |
| **Premium Connectors** | Track premium connector usage |

### SharePoint Sites

| Component | Description |
|-----------|-------------|
| **Allowed Sites** | Specific site URLs the agent can access |
| **Site Collections** | Entire collections if broader access needed |
| **Excluded Paths** | Specific folders/libraries to exclude |

### Dataverse Tables

| Component | Description |
|-----------|-------------|
| **Allowed Tables** | Specific tables agent can query |
| **Row-Level Scope** | Optional filters on allowed rows |
| **Column Restrictions** | Specific columns if needed |

### External APIs

| Component | Description |
|-----------|-------------|
| **Allowed Endpoints** | Approved external API URLs |
| **HTTP Methods** | Permitted methods (GET, POST, etc.) |
| **Authentication** | Expected auth patterns |

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows |
| **Dataverse capacity** | Scope and violation storage |
| **Microsoft 365 E5** or **E5 Compliance** | Unified Audit Log access |
| **Defender for Cloud Apps** | CloudAppEvents access |

### Permissions

| Role | Required For |
|------|--------------|
| **Purview Compliance Admin** | Audit log queries |
| **Security Reader** | Defender CloudAppEvents |
| **System Administrator** | Dataverse table creation |

## Quick Start

### 1. Deploy Solution Package

```powershell
# Package the solution using Power Platform CLI
pac solution pack --folder ./src/ScopeDriftMonitor --zipfile ./ScopeDriftMonitor_1_1_0.zip

# Import to your environment
pac solution import --path ./ScopeDriftMonitor_1_1_0.zip --environment "https://your-org.crm.dynamics.com"
```

### 2. Configure Environment Variables

After import, configure these environment variables in Power Apps:

| Variable | Value |
|----------|-------|
| `fsi_SDM_TenantId` | Your Microsoft Entra ID tenant ID |
| `fsi_SDM_DataverseEnvironment` | `https://your-org.crm.dynamics.com` |
| `fsi_SDM_TeamsGroupId` | Teams team ID for alerts |
| `fsi_SDM_TeamsChannelId` | Teams channel ID for alerts |
| `fsi_SDM_SecurityTeamEmail` | Security team email for approvals |
| `fsi_SDM_ClientId` | Azure AD application client ID (used by scripts; flows use connection references) |
| `fsi_SDM_ClientSecret` | Azure AD application client secret (used by scripts; flows use connection references) |
| `fsi_SDM_DetectionWindowMinutes` | Detection lookback window in minutes (default: 15) |
| `fsi_SDM_ActiveScopeStatus` | Option-set value for Active status on fsi_agentscope (default: 10002) |
| `fsi_SDM_ManagementApiEndpoint` | Office 365 Management API base URL (default: `https://manage.office.com`; use `https://manage.office365.us` for GCC High, `https://manage.protection.outlook.com` for DoD) |

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
.\scripts\Test-AlertDelivery.ps1 -Channel Both -TeamsWebhook "https://your-webhook-url" -EmailRecipient "security@contoso.com"
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
| **Scope Expansion** | Low | Agent scope was formally expanded |

### Detection Sources

| Source | Data Captured |
|--------|---------------|
| **Unified Audit Log** | CopilotInteraction events with connector details |
| **CloudAppEvents** | Defender detections including shadow IT |
| **SharePoint Audit** | Site/library access events |
| **Dataverse Audit** | Table read/write operations |

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

**Coverage:** Scope definitions ensure agents only access necessary data.

### GLBA 501(b)

> Safeguards to protect the security and confidentiality of customer records.

**Coverage:** Drift detection identifies unauthorized access to customer data.

### CCPA Purpose Limitation

> Data collected for specified purposes cannot be used for incompatible purposes.

**Coverage:** Scope enforcement ensures purpose-limited data access.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.4 - Advanced Connector Policies](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.4-advanced-connector-policies-for-copilot-studio.md) | DLP connector classification |
| [1.5 - DLP and Sensitivity Labels](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.5-data-loss-prevention-dlp-and-sensitivity-labels.md) | Sensitive data protection |
| [1.8 - Runtime Protection](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.8-runtime-protection-with-defender-for-cloud-apps.md) | Defender integration |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.1.0 | February 2026 | Production release with flows, scripts, and full documentation |
| 1.0.0 | February 2026 | Initial schema and concept |

## Support

For issues and feature requests, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - Scope Drift Monitor v1.1.0*
