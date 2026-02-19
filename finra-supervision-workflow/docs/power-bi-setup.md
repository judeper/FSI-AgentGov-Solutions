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

### Connect to Dataverse

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

Create these relationships when building manually:

| From | To | Cardinality | Cross Filter |
|------|-----|-------------|--------------|
| SupervisionLog.fsi_queueitem | SupervisionQueue.fsi_supervisionqueueid | Many-to-One | Single |

> **Important:** Do NOT create a direct relationship between SupervisionQueue and
> SupervisionConfig on `fsi_zone` alone. SupervisionConfig has multiple rows per zone
> (one per tier), so `fsi_zone` is not unique and cannot serve as the "one" side of a
> Many-to-One relationship. Instead, use `LOOKUPVALUE` DAX to retrieve config values
> by matching **both** zone and tier:
>
> ```dax
> Config SLA Hours =
> LOOKUPVALUE(
>     SupervisionConfig[fsi_slahours],
>     SupervisionConfig[fsi_zone], [fsi_zone],
>     SupervisionConfig[fsi_tier], [fsi_tier]
> )
> ```

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
    [fsi_state] IN {100000002, 100000004}, "Completed",
    [fsi_sladue] < NOW(), "Breached",
    [fsi_sladue] < NOW() + 2/24, "At Risk",
    "On Track"
)

Zone Label =
SWITCH(
    [fsi_zone],
    100000000, "Zone 1 - Personal",
    100000001, "Zone 2 - Team",
    100000002, "Zone 3 - Enterprise",
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
    SupervisionQueue[fsi_state] = 100000000
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
    CALCULATE(COUNTROWS(SupervisionQueue), SupervisionQueue[fsi_reviewoutcome] = 100000000),
    CALCULATE(COUNTROWS(SupervisionQueue), NOT(ISBLANK(SupervisionQueue[fsi_reviewoutcome]))),
    0
)

// Trend Metrics
Items This Week =
CALCULATE(
    COUNTROWS(SupervisionQueue),
    SupervisionQueue[fsi_queueddate] >= TODAY() - WEEKDAY(TODAY()) + 1
)

WoW Change =
VAR ThisWeek = [Items This Week]
VAR LastWeek = CALCULATE(
    COUNTROWS(SupervisionQueue),
    SupervisionQueue[fsi_queueddate] >= TODAY() - WEEKDAY(TODAY()) + 1 - 7,
    SupervisionQueue[fsi_queueddate] < TODAY() - WEEKDAY(TODAY()) + 1
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

## Dashboard Reference

The dashboard setup above includes:

- All pages configured
- Calculated columns and measures
- Relationships defined
- Conditional formatting guidance
- Default filters

> **Note:** No `.pbix` template file is included. Build the dashboard manually
> following the steps above. A pre-built template is planned for a future release.

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
