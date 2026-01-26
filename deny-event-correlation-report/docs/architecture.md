# Architecture

## Solution Overview

The Deny Event Correlation Report solution implements a batch processing pipeline that extracts deny events from three Microsoft data sources, stores them in a centralized location, and provides Power BI visualization for daily operational reporting.

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                                     │
├─────────────────┬─────────────────┬─────────────────────────────────────┤
│                 │                 │                                     │
│  Purview Audit  │   Purview DLP   │      Application Insights           │
│ (CopilotInter-  │  (DlpRuleMatch) │     (ContentFiltered)               │
│   action)       │                 │                                     │
│                 │                 │                                     │
└────────┬────────┴────────┬────────┴──────────────┬──────────────────────┘
         │                 │                       │
         │ Search-         │ Search-               │ REST API
         │ UnifiedAuditLog │ UnifiedAuditLog       │ (KQL)
         │                 │                       │
         ▼                 ▼                       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     EXTRACTION LAYER                                    │
│                                                                         │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐         │
│  │ Export-Copilot  │  │ Export-Dlp      │  │ Export-Rai      │         │
│  │ DenyEvents.ps1  │  │ CopilotEvents   │  │ Telemetry.ps1   │         │
│  │                 │  │ .ps1            │  │                 │         │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘         │
│           │                    │                    │                   │
│           └────────────────────┼────────────────────┘                   │
│                                │                                        │
│                    Invoke-DailyDenyReport.ps1                           │
│                       (Orchestration)                                   │
│                                │                                        │
└────────────────────────────────┼────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                       STORAGE LAYER                                     │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                   Azure Blob Storage                             │   │
│  │                   (or SharePoint)                                │   │
│  │                                                                  │   │
│  │  /deny-events/                                                   │   │
│  │  └── 2026-01-26/                                                 │   │
│  │      ├── CopilotDenyEvents-2026-01-26.csv                       │   │
│  │      ├── DlpCopilotEvents-2026-01-26.csv                        │   │
│  │      └── RaiTelemetry-2026-01-26.csv                            │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└────────────────────────────────┬────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    VISUALIZATION LAYER                                  │
│                                                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Power BI Service                             │   │
│  │                                                                  │   │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐        │   │
│  │  │ Executive     │  │ Event Details │  │ Correlation   │        │   │
│  │  │ Summary       │  │ Drill-down    │  │ Analysis      │        │   │
│  │  └───────────────┘  └───────────────┘  └───────────────┘        │   │
│  │                                                                  │   │
│  │           Daily Scheduled Refresh (7 AM)                         │   │
│  │                                                                  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Data Sources

#### Microsoft Purview Unified Audit Log

- **CopilotInteraction events** - Logged automatically when users interact with Copilot/Copilot Studio
- **Key deny indicators:**
  - `AccessedResources[].Status = "failure"`
  - `AccessedResources[].PolicyDetails` (present when blocked)
  - `AccessedResources[].XPIADetected = true`
  - `Messages[].JailbreakDetected = true`

#### Microsoft Purview DLP

- **DlpRuleMatch events** - Logged when DLP policies match
- **Copilot location:** "Microsoft 365 Copilot and Copilot Chat"
- **Key fields:** PolicyDetails, SensitiveInfoTypeData, ExceptionInfo (for overrides)

#### Application Insights

- **ContentFiltered events** - Logged by Copilot Studio when RAI blocks response
- **Per-agent configuration required** - No tenant-wide telemetry
- **Key fields:** FilterReason, FilterCategory, FilterSeverity

### 2. Extraction Layer

| Script | Purpose | API Used |
|--------|---------|----------|
| `Export-CopilotDenyEvents.ps1` | Extract CopilotInteraction deny events | Search-UnifiedAuditLog |
| `Export-DlpCopilotEvents.ps1` | Extract DLP matches for Copilot | Search-UnifiedAuditLog |
| `Export-RaiTelemetry.ps1` | Extract RAI telemetry | Application Insights REST API |
| `Invoke-DailyDenyReport.ps1` | Orchestrate all extractions | N/A |

### 3. Storage Layer

**Recommended:** Azure Blob Storage with immutable retention policy

- Supports SEC 17a-4 compliance
- Enables long-term retention (7+ years)
- Compatible with Power BI data source

**Alternative:** SharePoint Document Library with preservation hold

### 4. Visualization Layer

**Power BI Template** provides:

- Executive summary dashboard
- Event detail drill-down
- Multi-source correlation
- Daily trend analysis
- Alerting integration

## Deployment Options

### Option A: Azure Automation (Recommended for Production)

```
Azure Automation Account
├── Runbook: Invoke-DailyDenyReport
├── Schedule: Daily at 6:00 AM UTC
├── Credentials: Azure Key Vault reference
└── Variables: App Insights App ID, Storage Account
```

### Option B: Windows Task Scheduler (Development/Testing)

```
Task Scheduler
├── Task: Daily Deny Report
├── Trigger: Daily at 6:00 AM
├── Action: PowerShell.exe -File Invoke-DailyDenyReport.ps1
└── Credentials: Service account with Audit Reader role
```

### Option C: Power Automate (Low-Code Alternative)

```
Power Automate Flow
├── Trigger: Recurrence (Daily)
├── Action 1: Run PowerShell script (via on-premises data gateway)
├── Action 2: Upload files to SharePoint
└── Action 3: Notify compliance team
```

## Security Considerations

### Authentication

| Component | Authentication Method |
|-----------|----------------------|
| Exchange Online | Service principal or credential-based |
| Application Insights | API key (rotate every 90 days) |
| Azure Storage | Managed identity or SAS token |
| Power BI | Azure AD |

### Data Classification

The exported data may contain:

- User identities (PII)
- Agent identifiers (internal configuration)
- Policy names (internal configuration)
- SIT match indicators (may indicate sensitive data exposure)

**Recommendation:** Classify exports as "Internal - Confidential"

### Network Security

- All APIs use HTTPS
- Consider Private Link for Azure Storage
- Restrict Power BI workspace access to authorized viewers

## Scaling Considerations

### Audit Log Limits

- `Search-UnifiedAuditLog` has a 50,000 record limit per query
- For high-volume tenants, implement pagination or use Office 365 Management Activity API

### Application Insights Limits

- API queries limited to 500,000 rows per response
- Implement date-range partitioning for large volumes

### Power BI Refresh

- Standard refresh limited to 8 times per day
- Premium supports 48 refreshes per day
- Consider incremental refresh for large datasets

## Disaster Recovery

### Data Retention

- Azure Blob: Enable soft delete and versioning
- Maintain 7+ year retention for regulatory compliance
- Test restore procedures quarterly

### Runbook Recovery

- Store runbooks in source control (this repository)
- Document all Azure Automation configuration
- Test runbook deployment to new subscription

---

*FSI Agent Governance Framework v1.2 - January 2026*
