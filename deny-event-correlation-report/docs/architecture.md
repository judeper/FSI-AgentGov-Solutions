# Architecture

## Solution Overview

The Deny Event Correlation Report solution implements a batch processing pipeline that extracts deny events from four Microsoft data sources, stores them in a centralized location, and provides Power BI visualization for daily operational reporting.

## Data Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    DATA SOURCES                                          │
├─────────────────┬─────────────────┬─────────────────────────┬───────────────────────────┤
│                 │                 │                         │                           │
│  Purview Audit  │   Purview DLP   │  Application Insights   │  Defender CloudAppEvents  │
│ (CopilotInter-  │  (DlpRuleMatch) │   (ContentFiltered)     │  (XPIA/Jailbreak)         │
│   action)       │                 │                         │                           │
│                 │                 │                         │                           │
└────────┬────────┴────────┬────────┴────────────┬────────────┴──────────────┬────────────┘
         │                 │                     │                          │
         │ Search-         │ Search-             │ REST API                 │ Graph API
         │ UnifiedAuditLog │ UnifiedAuditLog     │ (KQL)                    │ (Advanced
         │                 │                     │                          │  Hunting)
         ▼                 ▼                     ▼                          ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              EXTRACTION LAYER                                            │
│                                                                                          │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐     │
│  │ Export-Copilot  │  │ Export-Dlp      │  │ Export-Rai      │  │ Export-Defender  │     │
│  │ DenyEvents.ps1  │  │ CopilotEvents   │  │ Telemetry.ps1   │  │ CopilotEvents   │     │
│  │                 │  │ .ps1            │  │                 │  │ .ps1            │     │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘     │
│           │                    │                    │                    │               │
│           └────────────────────┼────────────────────┼────────────────────┘               │
│                                │                    │                                    │
│                    Invoke-DailyDenyReport.ps1                                            │
│                       (Orchestration)                                                    │
│                                │                                                         │
└────────────────────────────────┼─────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                  STORAGE LAYER                                           │
│                                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐     │
│  │                          Azure Blob Storage                                      │     │
│  │                          (or SharePoint)                                         │     │
│  │                                                                                  │     │
│  │  /deny-events/                                                                   │     │
│  │  └── 2026-01-26/                                                                 │     │
│  │      ├── CopilotDenyEvents-2026-01-26.csv                                        │     │
│  │      ├── DlpCopilotEvents-2026-01-26.csv                                         │     │
│  │      ├── RaiTelemetry-2026-01-26.csv                                             │     │
│  │      └── DefenderCopilotEvents-2026-01-26.csv                                    │     │
│  │                                                                                  │     │
│  └─────────────────────────────────────────────────────────────────────────────────┘     │
│                                                                                          │
└────────────────────────────────┬─────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              VISUALIZATION LAYER                                         │
│                                                                                          │
│  ┌─────────────────────────────────────────────────────────────────────────────────┐     │
│  │                          Power BI Service                                        │     │
│  │                                                                                  │     │
│  │  ┌───────────────┐  ┌───────────────┐  ┌───────────────┐                         │     │
│  │  │ Executive     │  │ Event Details │  │ Correlation   │                         │     │
│  │  │ Summary       │  │ Drill-down    │  │ Analysis      │                         │     │
│  │  └───────────────┘  └───────────────┘  └───────────────┘                         │     │
│  │                                                                                  │     │
│  │           Daily Scheduled Refresh (7 AM)                                          │     │
│  │                                                                                  │     │
│  └─────────────────────────────────────────────────────────────────────────────────┘     │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. Data Sources

#### Microsoft Purview Unified Audit Log

- **CopilotInteraction events** - Logged automatically when users interact with Copilot/Copilot Studio
- **Key deny indicators:**
  - `AccessedResources[].Status = "failure"`
  - `AccessedResources[].PolicyDetails` (present when blocked)
  - `ResponseOutcome = "Blocked"` (when content was blocked)

> **Note:** The `XPIADetected` and `JailbreakDetected` fields are **not** part of the CopilotInteraction audit schema. Prompt injection and jailbreak detections are logged to **Defender CloudAppEvents** (requires Defender for Cloud Apps). See the CloudAppEvents Integration section below for details.

#### Microsoft Purview DLP

- **DlpRuleMatch events** - Logged when DLP policies match
- **Copilot location:** "Microsoft 365 Copilot and Copilot Chat"
- **Key fields:** PolicyDetails, SensitiveInfoTypeData, ExceptionInfo (for overrides)

#### Application Insights

- **ContentFiltered events** - Logged by Copilot Studio when RAI blocks response
- **Per-agent configuration required** - No tenant-wide telemetry
- **Key fields:** FilterReason, FilterCategory, FilterSeverity

#### Defender CloudAppEvents (Optional - Advanced)

- **Prompt injection detection** - UPIA (User Prompt Injection Attack) and XPIA (Cross-domain Prompt Injection Attack) events
- **Jailbreak detection** - Attempts to bypass model guardrails
- **Requires:** Defender for Cloud Apps license, enabled Copilot protection
- **Key query:**

```kql
CloudAppEvents
| where ActionType in ("CopilotInteraction", "CopilotMessageCreated")
| where RawEventData has "PromptInjection" or RawEventData has "Jailbreak"
| extend ThreatCategory = tostring(parse_json(RawEventData).ThreatCategory)
| project Timestamp, AccountDisplayName, Application, ThreatCategory
```

> **Note:** CloudAppEvents integration is separate from the core deny event extraction and requires additional licensing (Defender for Cloud Apps). Organizations without Defender may skip this data source.

### 2. Extraction Layer

| Script | Purpose | API Used |
|--------|---------|----------|
| `Connect-ExchangeOnlineHelper.ps1` | Shared EXO connection helper | ExchangeOnlineManagement |
| `Export-CopilotDenyEvents.ps1` | Extract CopilotInteraction deny events | Search-UnifiedAuditLog |
| `Export-DefenderCopilotEvents.ps1` | Extract Defender XPIA/Jailbreak events | Microsoft Graph Advanced Hunting |
| `Export-DlpCopilotEvents.ps1` | Extract DLP matches for Copilot | Search-UnifiedAuditLog |
| `Export-RaiTelemetry.ps1` | Extract RAI telemetry | Application Insights REST API |
| `Invoke-DailyDenyReport.ps1` | Orchestrate all extractions | N/A |

### 3. Storage Layer

**Recommended:** Azure Blob Storage with immutable retention policy

- Supports SEC 17a-4 compliance when configured with WORM-compliant immutable policies. Organizations should verify configuration meets their specific obligations.
- Enables long-term retention (7+ years)
- Compatible with Power BI data source

**Alternative:** SharePoint Document Library with preservation hold

### 4. Visualization Layer

**Power BI Template** provides:

> **Note:** The Power BI template (`.pbit`) is not included in this solution. Build a report in Power BI Desktop by connecting to your CSV exports or Log Analytics workspace using the queries in `kql-queries/correlation-analysis.kql`. The recommended report pages are:

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
├── Action: PowerShell.exe -File scripts\Invoke-DailyDenyReport.ps1
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

> **✅ Authentication Migration Complete: Microsoft Entra ID**
>
> Application Insights API key authentication was deprecated and `Export-RaiTelemetry.ps1` was migrated to Entra ID authentication on **February 4, 2026**. No `-ApiKey` parameter exists; the script uses `Connect-AzAccount` and `Get-AzAccessToken`.
>
> See [Authentication Migration](prerequisites.md#authentication-migration) for configuration details.
>
> *Migration completed: February 4, 2026*

| Component | Authentication Method | Deprecation Status |
|-----------|----------------------|-------------------|
| Exchange Online | Service principal or credential-based | Active |
| Application Insights | ~~API key~~ **Entra ID (OAuth 2.0)** | x-api-key deprecated March 31, 2026 |
| Defender CloudAppEvents | Entra ID (Defender APIs) | Active |
| Azure Storage | Managed identity or SAS token | Active |
| Power BI | Microsoft Entra ID | Active |

### Data Classification

The exported data may contain:

- User identities (PII)
- Agent identifiers (internal configuration)
- Policy names (internal configuration)
- SIT match indicators (may indicate sensitive data exposure)

**Recommendation:** Classify exports as "Internal - Confidential"

### Securing CSV Exports

CSV exports contain sensitive compliance data that requires protection:

| Field | Script | Risk |
|-------|--------|------|
| `UserId` (UPN) | All four extraction scripts | PII — identifies individual employees |
| `SitMatchDetails` | Export-DlpCopilotEvents.ps1 | Reveals sensitive info type match counts and confidence levels |
| `OverrideJustification` | Export-DlpCopilotEvents.ps1 | Free-text field — may contain sensitive context |
| `CustomDimensions` | Export-RaiTelemetry.ps1 | May contain conversation metadata |
| `ThreatCategory` | Export-DefenderCopilotEvents.ps1 | Reveals attack classification details |

**Recommended controls:**

1. **File system ACLs** — Restrict CSV output directories to authorized service accounts and compliance officers only
2. **Encryption at rest** — Store exports on BitLocker-encrypted volumes (Windows) or encrypted storage (Azure Blob with SSE)
3. **Retention policy** — Delete local CSV files after successful upload to Azure Blob Storage; apply immutable retention on blob tier
4. **Audit access** — Enable Azure Storage diagnostic logging to track who downloads exports
5. **Network controls** — Use Private Link for Azure Blob Storage; restrict Power BI workspace access to authorized viewers

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
