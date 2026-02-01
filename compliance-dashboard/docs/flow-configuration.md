# Flow Configuration

Power Automate flows for automated compliance data collection.

---

## Flow Overview

| Flow | Trigger | Purpose | Frequency |
|------|---------|---------|-----------|
| **CD-ScoreCalculator** | Scheduled | Calculate daily compliance scores | Daily (6 AM) |
| **CD-ExceptionMonitor** | Scheduled | Update exception SLA status | Hourly |
| **CD-EvidenceCollector** | Manual/Scheduled | Collect evidence from configured sources | Weekly |

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

- On failure: Send notification to Compliance Admin
- Retry policy: 3 attempts with exponential backoff

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
   - Filter: fsi_status IN (1, 2, 3)  // Open, In Progress, Pending Verification

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
- Channel: Email
- Content: Exception details, days remaining, action required

---

## Flow 3: CD-EvidenceCollector

Collects compliance evidence from configured sources.

### Trigger

**Recurrence** (default: weekly) or **Manual**

### Evidence Sources

| Source | API | Evidence Type |
|--------|-----|---------------|
| Purview Compliance Manager | Graph API | Assessment scores |
| Power Platform Admin Center | Power Platform API | Environment status |
| Azure AD | Graph API | Conditional Access policy status |
| Purview Audit Log | Office 365 Management API | Compliance events |

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
GET https://graph.microsoft.com/v1.0/compliance/ediscovery/cases
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

---

## Connection References

### Required Connections

| Connection | Purpose |
|------------|---------|
| **Dataverse** | Read/write compliance tables |
| **Office 365 Outlook** | Send email notifications |
| **Microsoft Teams** | Send Teams notifications |
| **HTTP with Azure AD** | Call Graph API and Power Platform API |

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
| `CD_NotificationEmail` | Email for compliance notifications | compliance@contoso.com |
| `CD_TeamsWebhook` | Teams webhook URL for alerts | (none) |
| `CD_DataverseEnvironment` | Dataverse environment URL | (current) |
| `CD_SLAMultiplier` | Multiplier for SLA calculations | 1.0 |

---

## Deployment

### Import Flows

1. Navigate to Power Automate
2. Click **Import** > **Import Package**
3. Upload `templates/ComplianceDashboard-Flows.zip`
4. Configure connection references
5. Set environment variables
6. Turn on flows

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

*Compliance Dashboard v1.0.0*
