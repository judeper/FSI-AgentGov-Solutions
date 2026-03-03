# Power BI Dashboard Setup

Deploy the FINRA Supervision Workflow dashboard for monitoring supervision metrics and compliance.

## Overview

The dashboard provides:

- **Queue Overview** - Current queue status, pending items by zone/tier
- **SLA Compliance** - SLA breach rates, average review times
- **Supervisor Performance** - Items reviewed per supervisor, turnaround time
- **Trend Analysis** - Volume trends, escalation patterns
- **Compliance Evidence** - Exportable reports for regulatory examination

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| License | Power BI Pro or Premium per user |
| Role | Power BI Admin (for workspace) |
| Data | SupervisionQueue and SupervisionLog tables populated |
| Connectivity | Access to Dataverse environment |

---

## Step 1: Create Power BI Workspace

1. Open [Power BI Service](https://app.powerbi.com)
2. Click **Workspaces** > **Create a workspace**
3. Configure:
   - Name: `FSI Supervision Workflow`
   - Description: `FINRA 3110 supervision monitoring`
   - License mode: Pro or Premium per user
4. Add members:
   - FSW Queue Manager group: Admin
   - FSW Auditor group: Viewer
   - CCO: Member

---

## Step 2: Configure Dataverse Connection

### Option A: Using Template

> **Note:** The `templates/SupervisionDashboard.pbit` template is not yet included in this release. Use Option B (Manual Connection) below to build the dashboard.

### Option B: Manual Connection (Recommended)

1. Open Power BI Desktop
2. **Get Data** > **Dataverse**
3. Enter environment URL
4. Select tables:
   - `fsi_supervisionqueue`
   - `fsi_supervisionlog`
   - `fsi_supervisionconfig`
5. Click **Load**

---

## Step 3: Configure Data Model

### Relationships

The template includes these relationships (create if building manually):

| From | To | Cardinality | Cross Filter |
|------|-----|-------------|--------------|
| SupervisionLog.fsi_queueitem | SupervisionQueue.fsi_supervisionqueueid | Many-to-One | Single |
| SupervisionQueue.ZoneTierKey | SupervisionConfig.ZoneTierKey | Many-to-One | Single |

> **Important:** The `fsi_zone` column alone is non-unique in SupervisionConfig (3 rows per zone). Create a composite key calculated column in both tables to establish an unambiguous relationship:

**SupervisionQueue Table:**

```dax
ZoneTierKey = [fsi_zone] & "-" & [fsi_tier]
```

**SupervisionConfig Table:**

```dax
ZoneTierKey = [fsi_zone] & "-" & [fsi_tier]
```

Create the relationship on `ZoneTierKey` (Many-to-One from SupervisionQueue to SupervisionConfig).

### Calculated Columns

**SupervisionQueue Table:**

```dax
Review Turnaround Hours =
IF(
    ISBLANK([fsi_revieweddate]),
    DATEDIFF([fsi_queueddate], NOW(), HOUR),
    DATEDIFF([fsi_queueddate], [fsi_revieweddate], HOUR)
)

SLA Status =
SWITCH(
    TRUE(),
    [fsi_state] IN {3, 5}, "Completed",
    [fsi_sladue] < NOW(), "Breached",
    [fsi_sladue] < NOW() + 2/24, "At Risk",
    "On Track"
)

Zone Label =
SWITCH(
    [fsi_zone],
    1, "Zone 1 - Personal",
    2, "Zone 2 - Team",
    3, "Zone 3 - Enterprise",
    "Unknown"
)
```

### Measures

```dax
// Queue Metrics
Total Queue Items = COUNTROWS(SupervisionQueue)

Pending Items =
CALCULATE(
    COUNTROWS(SupervisionQueue),
    SupervisionQueue[fsi_state] = 1
)

SLA Breach Rate =
DIVIDE(
    CALCULATE(COUNTROWS(SupervisionQueue), SupervisionQueue[SLA Status] = "Breached"),
    COUNTROWS(SupervisionQueue),
    0
)

Avg Review Time Hours =
AVERAGE(SupervisionQueue[Review Turnaround Hours])

// Completion Metrics
Items Reviewed Today =
CALCULATE(
    COUNTROWS(SupervisionQueue),
    SupervisionQueue[fsi_revieweddate] >= TODAY()
)

Approval Rate =
DIVIDE(
    CALCULATE(COUNTROWS(SupervisionQueue), SupervisionQueue[fsi_reviewoutcome] = 1),
    CALCULATE(COUNTROWS(SupervisionQueue), NOT(ISBLANK(SupervisionQueue[fsi_reviewoutcome]))),
    0
)

// Trend Metrics
Items This Week =
CALCULATE(
    COUNTROWS(SupervisionQueue),
    SupervisionQueue[fsi_queueddate] >= TODAY() - WEEKDAY(TODAY(), 2) + 1
)

WoW Change =
VAR ThisWeek = [Items This Week]
VAR LastWeek = CALCULATE(
    COUNTROWS(SupervisionQueue),
    SupervisionQueue[fsi_queueddate] >= TODAY() - WEEKDAY(TODAY(), 2) + 1 - 7,
    SupervisionQueue[fsi_queueddate] < TODAY() - WEEKDAY(TODAY(), 2) + 1
)
RETURN DIVIDE(ThisWeek - LastWeek, LastWeek, 0)
```

---

## Step 4: Build Dashboard Pages

### Page 1: Queue Overview

| Visual | Type | Data |
|--------|------|------|
| Pending Items | Card | [Pending Items] measure |
| SLA Breach Rate | Gauge | [SLA Breach Rate] measure, target 5% |
| Queue by Zone | Donut | Zone Label, Count of items |
| Queue by State | Bar | State, Count of items |
| Recent Items | Table | Queue Number, Agent Name, Zone, Queued Date, SLA Due |

### Page 2: SLA Compliance

| Visual | Type | Data |
|--------|------|------|
| SLA Status | Pie | SLA Status, Count |
| Breaches by Zone | Clustered Bar | Zone, Count where SLA Status = Breached |
| Avg Review Time | Line | Date (x-axis), Avg Review Time Hours (y-axis) |
| SLA Trend | Area | Date, SLA Breach Rate |

### Page 3: Supervisor Performance

| Visual | Type | Data |
|--------|------|------|
| Items per Supervisor | Bar | Assigned Principal, Count |
| Avg Turnaround by Supervisor | Bar | Reviewed By, Avg Review Time |
| Completion Rate by Supervisor | Table | Reviewed By, Total Reviewed, Approval Rate |
| Supervisor Workload | Matrix | Supervisor (rows), Zone (columns), Count (values) |

### Page 4: Compliance Evidence

| Visual | Type | Data |
|--------|------|------|
| Date Range Slicer | Slicer | Queued Date |
| Zone Slicer | Slicer | Zone |
| Full Queue Export | Table | All columns, enable export |
| Audit Log Export | Table | All SupervisionLog columns |

---

## Step 5: Configure Refresh Schedule

1. Publish report to Power BI Service
2. Navigate to workspace > Dataset settings
3. Configure:
   - Gateway: Not required (Dataverse is cloud)
   - Credentials: OAuth2 organizational account
   - Scheduled refresh: Every 30 minutes

### Refresh Schedule Settings

| Setting | Value |
|---------|-------|
| Time zone | (UTC-05:00) Eastern Time |
| Frequency | Daily |
| Times | Every 30 minutes during business hours |

---

## Step 6: Configure Alerts

### SLA Breach Alert

1. Navigate to Queue Overview page
2. Click SLA Breach Rate gauge > **...** > **Manage alerts**
3. Configure:
   - Title: SLA Breach Threshold Exceeded
   - Condition: Above 10%
   - Frequency: Once an hour at most
   - Notification: Email + Teams

### Pending Queue Alert

1. Click Pending Items card > **...** > **Manage alerts**
2. Configure:
   - Title: High Pending Queue Volume
   - Condition: Above 50 items
   - Notification: Email to Queue Manager

---

## Step 7: Share Dashboard

### Internal Sharing

1. Open report in Power BI Service
2. Click **Share**
3. Add recipients:
   - FSW Queue Manager group
   - CCO
   - Compliance team

### Embed in Teams (Optional)

1. Navigate to Teams channel
2. Add tab > Power BI
3. Select workspace and report
4. Choose Page 1 (Queue Overview)

### Export for Examination

For regulatory examinations, export compliance evidence:

1. Navigate to Compliance Evidence page
2. Set date range filters
3. Export each table to CSV
4. Include in examination evidence package

---

## Dashboard Template

> **Note:** The `templates/SupervisionDashboard.pbit` template is planned for a future release. Build the dashboard manually using the steps above (Option B) and the calculated columns, measures, and page layouts documented in Steps 3-4.

---

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| No data showing | Empty tables | Verify queue has data |
| Connection failed | Credentials expired | Re-authenticate in dataset settings |
| Refresh failed | Permissions | Verify account has Dataverse read access |
| Missing columns | Schema changed | Re-import tables |

---

## Related Resources

- [Power BI Documentation](https://learn.microsoft.com/en-us/power-bi/)
- [Dataverse Connector](https://learn.microsoft.com/en-us/power-bi/connect-data/service-connect-to-dataverse)
- [Control 3.3: Compliance Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.3-compliance-reporting-and-regulatory-evidence.md)
