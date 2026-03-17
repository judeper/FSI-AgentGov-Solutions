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
| 4 | List rows | Table: `fsi_controlassessments`, Filter: Latest per control |
| 5 | Apply to each | Loop through assessments |
| 6 | Condition | Check if status != Not Applicable |
| 7 | Compose | Calculate weighted score |
| 8 | Increment variable | Add to totals |
| 9 | Compose | Calculate final scores |
| 10 | Create row | Table: `fsi_compliancescore` |

### Error Handling

- On failure: Send notification to Compliance Admin via `CD_NotificationEmail` environment variable
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
   - Calculate DaysOpen = DateDiff(createdon, today)
   - Get SLA days based on severity

   IF DaysOpen > SLA THEN
     - Set fsi_slastatus = Breached
     - IF previous status != Breached THEN
       - Send breach notification
     END IF
   ELSE IF DaysOpen > SLA × 0.8 THEN
     - Set fsi_slastatus = At Risk
     - IF previous status == On Track THEN
       - Send warning notification
     END IF
   ELSE
     - Set fsi_slastatus = On Track
   END IF

   - Update fsi_daysopen
   - Update fsi_slastatus

3. Send daily summary if any breached exceptions
```

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
| Purview Compliance Manager | Graph API | Assessment scores |
| Power Platform Admin Center | Power Platform API | Environment status |
| Microsoft Entra ID | Graph API | Conditional Access policy status |
| Purview Audit Log | Office 365 Management API | Compliance events |
| Exchange Online | Graph API (via Get-ExchangeComplianceData.ps1) | Forwarding rules, DLP alerts, mailbox access |

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
```http
GET https://graph.microsoft.com/v1.0/compliance/complianceManager/assessments
Authorization: Bearer {token}
```

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

> **Note:** For comprehensive Exchange evidence collection, use `Get-ExchangeComplianceData.ps1` (in `scripts/`) which handles pagination, retry logic, and multi-signal aggregation. The CD-EvidenceCollector flow can invoke the script output JSON via a scheduled task or import the evidence file directly.

---

## Connection References

### Required Connections

| Connection | Purpose |
|------------|---------|
| **Dataverse** | Read/write compliance tables |
| **Office 365 Outlook** | Send email notifications |
| **Microsoft Teams** | Send Teams notifications |

> **Note:** The **HTTP with Microsoft Entra ID** connection is only required for the planned CD-EvidenceCollector flow (not yet implemented). The current solution package (`connectionreferences.json`) does not include it. Do not create this connection unless CD-EvidenceCollector is deployed.

### Service Principal Connection

For Graph API and Power Platform API calls:

1. Create connection using service principal
2. Use client credentials flow
3. Reference client ID and secret from Azure Key Vault

```json
{
  "connectionType": "servicePrincipal",
  "tenantId": "{tenant-id}",
  "clientId": "{client-id}",
  "clientSecret": "@Microsoft.KeyVault(SecretUri=https://vault.vault.azure.net/secrets/CD-ClientSecret)"
}
```

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `CD_NotificationEmail` | Email for compliance notifications | (none — required during import) |
| `CD_TeamsWebhook` | Not currently used — Teams alerts use the shared\_teams connector directly (PostMessageToConversation). Setting this value has no effect. | (none) |
| `CD_DataverseEnvironment` | Deprecated — will be removed in next major release. Not referenced by any flow (flows use connection reference). Safe to skip during import. | (current) |
| `CD_SLAMultiplier` | Reserved for future SLA configurability (not yet referenced by flows) | 1.0 |

---

## Deployment

### Import Flows

The flows are deployed as part of the Power Apps solution package (not as a standalone Power Automate import package).

1. Navigate to [Power Apps maker portal](https://make.powerapps.com)
2. Select **Solutions** > **Import solution**
3. Upload the exported solution zip (see `templates/README.md` for how to create `ComplianceDashboard_1_0_0.zip` from a dev environment)
4. Configure connection references when prompted
5. Set environment variables when prompted
6. After import, navigate to **Power Automate** and turn on the flows

### Post-Import Configuration

1. Verify connection references are valid
2. Test each flow manually
3. Review error handling email recipients
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

### SLA Multiplier Not Yet Referenced

The `fsi_CD_SLAMultiplier` environment variable is reserved for future SLA configurability but is not yet referenced by any flow. SLA periods are currently hardcoded in `Initialize_SLA_Days` (Critical=7, High=14, Medium=30, Low=90).

### Bracket Characters in Package Filenames

The `[Content_Types].xml` file in the solution package contains bracket characters that require `-LiteralPath` or backtick escaping in PowerShell. Deployment scripts should use `Get-Content -LiteralPath` or escape as `` `[Content_Types`].xml `` to avoid glob expansion errors.

### Dead Variable: CD_TeamsWebhook

The `Initialize_CD_TeamsWebhook` action (CD-ExceptionMonitor) reads the `fsi_CD_TeamsWebhook` environment variable into a flow variable, but no subsequent action references `CD_TeamsWebhook`. Teams notifications use the `shared_teams` connector directly (`PostMessageToConversation`). Removing this initialization requires adjusting the `Scope_Main` runAfter chain (which depends on `Initialize_CD_TeamsWebhook`), so this is an architectural cleanup rather than a simple deletion. The action is annotated with a description documenting this status.

### Daily Summary Fixed to 09:00 UTC

The `Condition_Send_Daily_Summary` action evaluates `formatDateTime(utcNow(), 'HH') == "09"`, restricting the daily breach summary email to the 09:00 UTC hourly run. Organizations in time zones far from UTC may prefer to adjust this value. Changing the hour requires editing the condition expression in `CD-ExceptionMonitor.json` (the `"09"` literal in `Condition_Send_Daily_Summary`).

---

*Compliance Dashboard v1.0.0*
