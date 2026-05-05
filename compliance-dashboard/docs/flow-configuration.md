# Flow Configuration

Power Automate flows for automated compliance data collection.

---

## Flow Overview

| Flow | Trigger | Purpose | Frequency |
|------|---------|---------|-----------|
| **CD-ScoreCalculator** | Scheduled | Calculate daily compliance scores | Daily (6 AM) |
| **CD-ExceptionMonitor** | Scheduled | Update exception SLA status | Hourly |
| **CD-EvidenceCollector** | *Planned* | Collect evidence from configured sources | *Not yet implemented* |

---

## Flow 1: CD-ScoreCalculator

Calculates and stores daily compliance scores for trend analysis.

### Trigger

**Recurrence**
- Frequency: Day
- Interval: 1
- Start time: 06:00 UTC
- Time zone: UTC

### Logic

```
1. Initialize variables
   - TotalWeightedScore = 0
   - TotalWeight = 0
   - PillarScores = {}
   - ZoneScores = {}

2. List all control assessments (most recent per control)
   - Filter: Latest assessment per fsi_controlmasterid
   - Expand: fsi_controlmaster for weight and pillar
   - For large datasets, prefer Dataverse FetchXML `aggregate='true'` or Web API `$apply=groupby(...,aggregate(...))` patterns partitioned by date/zone to avoid the Dataverse 50,000-record aggregate evaluation limit

3. For each assessment:
   IF status != "Not Applicable" THEN
     - WeightedScore = Score × ControlWeight × ZoneMultiplier
     - TotalWeightedScore += WeightedScore
     - TotalWeight += ControlWeight × ZoneMultiplier
     - Update pillar subtotals
     - Update zone subtotals
   END IF

4. Calculate final scores:
   - OverallScore = TotalWeightedScore / TotalWeight
   - PillarScores = PillarWeightedSum / PillarWeight
   - ZoneScores = ZoneWeightedSum / ZoneWeight

5. Create fsi_compliancescore record:
   {
     "fsi_scoredate": today,
     "fsi_overallscore": OverallScore,
     "fsi_pillar1score": PillarScores[1],
     "fsi_pillar2score": PillarScores[2],
     "fsi_pillar3score": PillarScores[3],
     "fsi_pillar4score": PillarScores[4],
     "fsi_zone1score": ZoneScores[1],
     "fsi_zone2score": ZoneScores[2],
     "fsi_zone3score": ZoneScores[3],
     "fsi_compliantcount": count(status=Compliant),
     "fsi_partialcount": count(status=Partial),
     "fsi_noncompliantcount": count(status=Non-Compliant),
     "fsi_exceptioncount": count(openExceptions)
   }
```

### Actions

| Step | Action | Configuration |
|------|--------|---------------|
| 1 | Initialize variable | Name: `TotalWeightedScore`, Type: Float, Value: 0 |
| 2 | Initialize variable | Name: `TotalWeight`, Type: Float, Value: 0 |
| 3 | Initialize variable | Name: `PillarScores`, Type: Object |
| 4 | List rows | Table: `fsi_controlassessment` (singular logical name in Power Automate's "Table name" picker), Filter: Latest per control |
| 5 | Apply to each | Loop through assessments |
| 6 | Condition | Check if status != Not Applicable |
| 7 | Compose | Calculate weighted score |
| 8 | Increment variable | Add to totals |
| 9 | Compose | Calculate final scores |
| 10 | Create row | Table: `fsi_compliancescore` |

### Error Handling

- On failure: Send notification to Compliance Admin via `fsi_CD_NotificationEmail` environment variable
- Retry policy: 3 attempts with exponential backoff (10s initial, 1m max) on Dataverse actions
- Scope-based error handler sends failure alert email when List, Loop, or Create actions fail

---

## Flow 2: CD-ExceptionMonitor

Updates exception SLA status and sends alerts for at-risk items.

### Trigger

**Recurrence**
- Frequency: Hour
- Interval: 1

### Logic

```
1. List all open exceptions
   - Filter: fsi_exceptionstatus IN (1, 2, 3)  // Open, In Progress, Pending Verification

2. For each exception:
   - DaysOpen and SLA status are exposed as **calculated columns** (`fsi_daysopen`, `fsi_slastatus`); they are computed by Dataverse and cannot be written from a flow. The flow only reads them and decides whether to send notifications.

   IF fsi_slastatus == Breached AND previous status != Breached THEN
     - Send breach notification
   ELSE IF fsi_slastatus == At Risk AND previous status == On Track THEN
     - Send warning notification
   END IF

3. Send daily summary if any breached exceptions
```

> **Note on calculated columns:** `fsi_daysopen` and `fsi_slastatus` are defined as Dataverse calculated columns in [Dataverse Schema](dataverse-schema.md). Calculated columns cannot be written via the Web API or the Dataverse connector; the flow reads the computed values and tracks state transitions in a separate `fsi_lastnotifiedstatus` column (or in another tracking mechanism). If you intend the flow to write `fsi_slastatus` directly, change the column to a non-calculated choice in your schema before building the flow.

### SLA Configuration

| Severity | SLA Days | At Risk Threshold |
|----------|----------|-------------------|
| Critical | 7 | 5.6 days (80%) |
| High | 14 | 11.2 days (80%) |
| Medium | 30 | 24 days (80%) |
| Low | 90 | 72 days (80%) |

### Notifications

**SLA Breach Alert**
- Recipients: Exception owner, Compliance Admin
- Channel: Email + Teams
- Content: Exception details, days overdue, remediation plan link

**At Risk Warning**
- Recipients: Exception owner
- Channel: Email + Teams
- Content: Exception details, days remaining, action required

---

## Flow 3: CD-EvidenceCollector (Planned — Not Yet Implemented)

> **Note:** This flow is planned for a future release. The flow definition does not yet exist in the solution package. The design below documents the intended behavior.

Collects compliance evidence from configured sources.

### Trigger

**Recurrence** (default: weekly) or **Manual**

### Evidence Sources

| Source | API | Evidence Type |
|--------|-----|---------------|
| Purview Compliance Manager | Purview portal Excel export | Assessment score and improvement-action snapshots (manual import until a supported API is published) |
| Microsoft 365 admin center reports | Microsoft Graph Reports API | Usage reports, Copilot usage, and agent usage where available |
| Power Platform Admin Center | Power Platform API / admin center exports | Environment status, capacity, and DLP posture |
| Microsoft Entra ID | Graph API | Conditional Access policy status |
| Purview Audit Log | Office 365 Management API | Compliance events |
| Exchange Online | Microsoft Graph plus Security & Compliance PowerShell | Forwarding rules, DLP alerts, mailbox indicators, compliance search, eDiscovery, and retention policy evidence |

### Logic

```
1. Get list of controls requiring evidence refresh
   - Filter: fsi_nextreviewdate <= today + 7

2. For each control:
   - Determine evidence sources based on control category

   IF control.category == "Native Feature" THEN
     - Call appropriate API to get current configuration
     - Generate configuration export
     - Calculate SHA-256 hash
     - Create evidence record
   END IF

3. Update assessment with new evidence count
```

### API Calls

**Purview Compliance Manager**

Current Microsoft Learn guidance documents Compliance Manager assessment and improvement-action exports through the Purview portal Excel export workflow. Do not build the flow against undocumented Compliance Manager Graph endpoints or permissions for assessment score export as of 2026-Q2.

Recommended interim pattern:

1. Export assessment or improvement-action workbooks from Compliance Manager.
2. Store the workbook in a governed SharePoint/OneDrive location with retention labels.
3. Import normalized rows into `fsi_complianceevidence` and link them to `fsi_controlassessment`.

**Microsoft 365 usage reports (Graph)**
```http
GET https://graph.microsoft.com/v1.0/copilot/reports/getMicrosoft365CopilotUserCountSummary(period='D30')?$format=application/json
GET https://graph.microsoft.com/v1.0/reports/getOffice365ActiveUserDetail(period='D30')
Authorization: Bearer {token}
```

Use `Reports.Read.All` and the least-privileged Microsoft Entra role required for delegated reads. For production dashboards, prefer the v1.0 `/copilot/reports/...` APIs when available instead of legacy beta `/reports/...` Copilot endpoints.

**Power Platform Environments**
```http
GET https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments
Authorization: Bearer {token}
```

**Conditional Access Policies**
```http
GET https://graph.microsoft.com/v1.0/identity/conditionalAccess/policies
Authorization: Bearer {token}
```

**Exchange Online — External Forwarding Rules**
```http
GET https://graph.microsoft.com/v1.0/users/{id}/mailFolders/inbox/messageRules
Authorization: Bearer {token}
```

**Exchange Online — eDiscovery, compliance search, and retention policy evidence**
```powershell
Connect-IPPSSession -AppId <app-id> -CertificateThumbprint <thumbprint> -Organization <tenant>.onmicrosoft.com
Get-RetentionCompliancePolicy -DistributionDetail
New-ComplianceSearch -Name "Agent Evidence Review" -ExchangeLocation All -ContentMatchQuery '<query>'
Start-ComplianceSearch -Identity "Agent Evidence Review"
```

> **Note:** For Graph-backed Exchange evidence collection, use `Get-ExchangeComplianceData.ps1` (in `scripts/`) which handles pagination, retry logic, and multi-signal aggregation. Use Security & Compliance PowerShell with certificate-based app authentication for compliance search, eDiscovery, and retention evidence that Graph does not expose. The CD-EvidenceCollector flow can invoke script output JSON via a scheduled task or import the evidence file directly.

---

## Connection References

### Required Connections

| Connection | Purpose |
|------------|---------|
| **Microsoft Dataverse** | Read/write compliance tables |
| **Office 365 Outlook** | Send email notifications (used by both flows) |
| **Microsoft Teams** | Send Teams notifications (used by CD-ExceptionMonitor) |

> **Note:** A future `CD-EvidenceCollector` flow (planned, not yet implemented) is expected to require an HTTP-with-Microsoft-Entra-ID connection for Microsoft Graph and Power Platform API calls. Do not create that connection yet.

### Service Principal Connection

For Graph API and Power Platform API calls:

1. Prefer managed identity for Azure-hosted flows or workload identity federation for CI.
2. Use certificate-based app authentication for Exchange Online Security & Compliance PowerShell.
3. Use client secrets only as a legacy dev-only fallback and store them in Azure Key Vault if temporarily required.

```json
{
  "connectionType": "managedIdentityOrWorkloadIdentity",
  "tenantId": "{tenant-id}",
  "clientId": "{managed-identity-or-app-client-id}",
  "credential": "managed identity, workload identity federation, or certificate; client secret is legacy dev-only"
}
```

---

## Environment Variables

All environment variables follow the Dataverse publisher prefix pattern `fsi_CD_<Name>` (display name without the prefix in parentheses).

| Schema name | Display name | Description | Default |
|-------------|--------------|-------------|---------|
| `fsi_CD_NotificationEmail` | CD Notification Email | Email for compliance notifications | (none — required during deployment) |
| `fsi_CD_TeamsWebhook` | CD Teams Webhook | Reserved for future use; not currently consumed by any flow (Teams alerts use the `shared_teams` connector directly via `PostMessageToConversation`). Setting this value has no effect today. | (none) |
| `fsi_CD_DataverseEnvironment` | CD Dataverse Environment | Deprecated; flows resolve the environment via the connection reference. Safe to skip. | (none) |
| `fsi_CD_SLAMultiplier` | CD SLA Multiplier | Reserved for future SLA configurability; not yet referenced by flows. | 1.0 |

> **Note:** Power Automate's "Get environment variable" action expects the **schema name** (`fsi_CD_*`). Dropdown pickers may show the **display name** (the value in the second column above) — both refer to the same record.

---

## Deployment

This solution does not ship a Power Automate solution package. Build each flow manually in the Power Automate maker portal following the trigger/action notes above, save it into your Compliance Dashboard solution, and configure the connection references and environment variables.

### Build steps

1. Navigate to [Power Automate maker portal](https://make.powerautomate.com)
2. Open or create the **Compliance Dashboard** solution
3. Build the Dataverse schema first (see [Dataverse Schema](dataverse-schema.md))
4. Build each flow described above using the listed triggers, steps, and connection references
5. Configure environment variables (`fsi_CD_*`)
6. Turn on the trigger for each flow

### Post-build configuration

1. Verify connection references are valid
2. Test each flow manually
3. Review error-handling email recipients
4. Enable scheduled triggers

---

## Monitoring

### Flow Run History

Monitor flow runs in Power Automate:
- Success rate target: >99%
- Average duration: <5 minutes
- Error notification: Immediate

### Dataverse Data Validation

Daily validation checks:
- Score records created for each day
- Exception SLA status updated
- No orphaned records

---

## Known Limitations

### No Self-Audit Logging

The solution monitors external compliance controls but does not currently log its own operations (flow executions, SLA transitions, notification outcomes) to a Dataverse audit table. Organizations requiring auditable records of dashboard operations should enable Power Automate flow run logging via the Center of Excellence toolkit or implement a custom `fsi_flowauditlog` table.

### Pagination Limits

All `ListRecords` actions use `minimumItemCount: 100000` (Power Automate maximum). Environments exceeding 100,000 open exceptions or control assessments will experience silent result truncation.

**Truncation detection:** In the flow run history, check the output of each `ListRecords` action. If the returned array length equals exactly 100,000, results are likely truncated. Specifically:
- `CD-ExceptionMonitor`: Check `length(outputs('List_Open_Exceptions')?['body/value'])` and `length(outputs('List_All_Breached_Exceptions')?['body/value'])`
- `CD-ScoreCalculator`: Check `length(outputs('List_Control_Assessments')?['body/value'])` and `length(outputs('Get_Open_Exception_Count')?['body/value'])`

**Mitigation:** Enable Dataverse table archival or add date-range filters to reduce result sets below the 100,000 ceiling.

### N+1 Update Pattern

`CD-ExceptionMonitor` issues individual `UpdateRecord` calls per exception inside `Apply_to_each`. For large exception volumes, migrating to Dataverse batch changeset operations (`$batch` endpoint) would reduce API calls and improve throughput.

### Calculated Columns are Read-Only

`fsi_daysopen` and `fsi_slastatus` are documented in [Dataverse Schema](dataverse-schema.md) as **calculated** columns; calculated columns cannot be updated through the Dataverse Web API or the Dataverse connector. If you need the SLA flow to maintain these values directly, change them to standard columns in your schema before building the flow. The pseudo-code above for Flow 2 assumes either (a) the columns are non-calculated in your environment, or (b) the SLA logic is implemented as a Dataverse calculated-column formula and the flow only handles notifications.

### SLA Multiplier Not Yet Referenced

The `fsi_CD_SLAMultiplier` environment variable is reserved for future SLA configurability but is not yet referenced by any flow. SLA periods are currently hardcoded in `Initialize_SLA_Days` (Critical=7, High=14, Medium=30, Low=90).

### Daily Summary Fixed to 09:00 UTC

The `Condition_Send_Daily_Summary` action evaluates `formatDateTime(utcNow(), 'HH') == "09"`, restricting the daily breach summary email to the 09:00 UTC hourly run. Organizations in time zones far from UTC may prefer to adjust this value when building the flow.

---

*Compliance Dashboard v1.0.4*
