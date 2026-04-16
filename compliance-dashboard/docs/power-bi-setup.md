# Power BI Setup

Deployment and configuration guide for the Compliance Dashboard Power BI report.

---

## Overview

The Compliance Dashboard provides five report pages:

1. **Executive Summary** - Overall compliance posture
2. **Pillar Overview** - Breakdown by governance pillar
3. **Control Details** - Individual control status
4. **Exception Tracker** - Open exceptions and remediation
5. **Trend Analysis** - Historical compliance trends

---

## Prerequisites

- Power BI Desktop (latest version)
- Power BI Pro or Premium license
- Dataverse tables deployed (see [Dataverse Schema](dataverse-schema.md))
- Network access to Dataverse environment

---

## Deployment Steps

### Step 1: Download Template

Download the Power BI template file:
- `templates/ComplianceDashboard.pbit`

### Step 2: Open in Power BI Desktop

1. Open Power BI Desktop
2. Click **File** > **Open** > select `ComplianceDashboard.pbit`
3. Template will prompt for parameters

### Step 3: Configure Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `DataverseEnvironmentUrl` | Your Dataverse environment URL | `https://contoso.crm.dynamics.com` |
| `TenantId` | Your Microsoft Entra ID tenant ID | `12345678-1234-1234-1234-123456789abc` |

### Step 4: Authenticate

1. Click **Connect**
2. Sign in with organizational account
3. Select **Organizational account** for Dataverse connection
4. Click **Connect**

### Step 5: Refresh Data

1. Click **Refresh** to load current data
2. Verify data loads successfully
3. Check for any error indicators

### Step 6: Publish to Power BI Service

1. Click **Publish**
2. Select destination workspace
3. Wait for publish to complete
4. Click link to open in Power BI Service

---

## Data Model

### Tables

| Table | Source | Refresh Mode |
|-------|--------|--------------|
| ControlMaster | fsi_controlmaster | Import |
| ControlAssessment | fsi_controlassessment | Import |
| ComplianceScore | fsi_compliancescore | Import |
| ComplianceException | fsi_complianceexception | Import |
| ComplianceEvidence | fsi_complianceevidence | Import |
| DateTable | Generated | Import |

### Relationships

```
DateTable ──────┬──────── ComplianceScore (fsi_scoredate)
                │
ControlMaster ──┼──────── ControlAssessment (fsi_controlmasterid)
                │
ControlAssessment ──┬──── ComplianceException (fsi_controlassessmentid)
                    │
                    └──── ComplianceEvidence (fsi_controlassessmentid)
```

### Date Table

Auto-generated date table for time intelligence:

```dax
DateTable =
ADDCOLUMNS(
    CALENDAR(DATE(2025, 1, 1), DATE(2027, 12, 31)),
    "Year", YEAR([Date]),
    "Month", MONTH([Date]),
    "MonthName", FORMAT([Date], "MMMM"),
    "Quarter", "Q" & QUARTER([Date]),
    "WeekNum", WEEKNUM([Date]),
    "DayOfWeek", WEEKDAY([Date]),
    "IsCurrentMonth", IF(MONTH([Date]) = MONTH(TODAY()) && YEAR([Date]) = YEAR(TODAY()), TRUE, FALSE)
)
```

---

## Report Pages

### Page 1: Executive Summary

**Visuals:**

| Visual | Type | Data |
|--------|------|------|
| Overall Score | Card | Latest overall score |
| Score Trend | Line chart | 30-day score trend |
| Pillar Scores | Column chart | Score by pillar |
| Zone Scores | Donut chart | Score by zone |
| Exception Count | Card | Open exceptions |
| SLA Status | Stacked bar | Exceptions by SLA status |

**Filters:**
- Date range (last 30/60/90 days)

### Page 2: Pillar Overview

**Visuals:**

| Visual | Type | Data |
|--------|------|------|
| Pillar Cards | Multi-row card | Score per pillar |
| Control Status Matrix | Matrix | Controls by pillar × status |
| Pillar Trend | Line chart | Pillar scores over time |
| Non-Compliant Controls | Table | List of non-compliant controls |

**Filters:**
- Pillar selector
- Zone selector

### Page 3: Control Details

**Visuals:**

| Visual | Type | Data |
|--------|------|------|
| Control List | Table | All controls with status |
| Assessment History | Line chart | Selected control over time |
| Evidence List | Table | Evidence for selected control |
| Regulatory Tags | Slicer | Filter by regulation |

**Filters:**
- Pillar
- Zone
- Status
- Regulatory reference

**Drill-through:**
- Click control to see full assessment history

### Page 4: Exception Tracker

**Visuals:**

| Visual | Type | Data |
|--------|------|------|
| Open Exceptions | Card | Count of open exceptions |
| SLA Distribution | Pie chart | By SLA status |
| Exception Table | Table | Full exception list |
| Age Distribution | Histogram | Days open distribution |
| Owner Workload | Bar chart | Exceptions per owner |

**Filters:**
- Severity
- Status
- Owner
- SLA Status

### Page 5: Trend Analysis

**Visuals:**

| Visual | Type | Data |
|--------|------|------|
| Score Trend | Line chart | Overall score over time |
| Pillar Trends | Multi-line chart | All pillars over time |
| MoM Change | KPI | Month-over-month change |
| Forecast | Line chart | 30-day forecast (optional) |
| Control Status Changes | Waterfall | Changes in status counts |

**Filters:**
- Date range
- Pillar
- Zone

---

## DAX Measures

See [DAX Measures](dax-measures.md) for complete measure definitions.

### Key Measures

**Overall Compliance Score**
```dax
Overall Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_overallscore]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )
```

**Score Trend**
```dax
Score Trend =
VAR CurrentScore = [Overall Score]
VAR PriorScore =
    CALCULATE(
        [Overall Score],
        DATEADD(DateTable[Date], -30, DAY)
    )
RETURN
    CurrentScore - PriorScore
```

**Exception SLA %**
```dax
SLA Compliance % =
VAR OnTrack =
    CALCULATE(
        COUNTROWS(ComplianceException),
        ComplianceException[fsi_slastatus] = 1,
        ComplianceException[fsi_exceptionstatus] IN {1, 2, 3}
    )
VAR Total =
    CALCULATE(
        COUNTROWS(ComplianceException),
        ComplianceException[fsi_exceptionstatus] IN {1, 2, 3}
    )
RETURN
    DIVIDE(OnTrack, Total, 1)
```

---

## Scheduled Refresh

### Configure in Power BI Service

1. Go to dataset settings
2. Click **Scheduled refresh**
3. Configure:
   - Refresh frequency: Daily
   - Time: 7:00 AM (after score calculation flow)
   - Notify on failure: Yes

### Gateway Requirements

If Dataverse is behind a firewall:
- Install On-premises data gateway
- Configure gateway connection
- Map Dataverse data source

For cloud-only deployments:
- No gateway required
- Use organizational account authentication

---

## Row-Level Security (RLS)

### Role Definitions

**Zone Viewer**
```dax
// Users can only see data for their assigned zones
[Zone] IN {USERPRINCIPALNAME() zone assignments}
```

**Pillar Owner**
```dax
// Users can only see data for their assigned pillars
[Pillar] IN {USERPRINCIPALNAME() pillar assignments}
```

### Implementation

1. Open report in Power BI Desktop
2. Click **Modeling** > **Manage roles**
3. Create roles with DAX filters
4. Publish report
5. In Power BI Service, assign users to roles

---

## Customization

### Adding Custom Controls

1. Add rows to `fsi_controlmaster` table in Dataverse
2. Refresh Power BI dataset
3. New controls appear automatically

### Modifying Scoring Weights

1. Update `fsi_weight` in `fsi_controlmaster`
2. Score calculation flow uses updated weights
3. Refresh Power BI to see changes

### Custom Visuals

Recommended custom visuals:
- **Bullet Chart** - For target vs. actual scores
- **Chiclet Slicer** - For pillar/zone selection
- **Card with States** - For score with conditional formatting

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No data showing | Verify Dataverse connection, check data exists |
| Refresh fails | Check credentials, verify network access |
| Slow performance | Reduce date range, use aggregations |
| Missing controls | Verify control master data loaded |

---

## Export and Sharing

### Export Options

- **PDF** - Static report snapshot
- **PowerPoint** - Presentation format
- **Excel** - Underlying data tables

### Sharing Options

- **Workspace access** - Share entire workspace
- **Direct sharing** - Share specific report
- **Embed** - Embed in Teams or SharePoint
- **Publish to web** - Public access (not recommended for compliance data)

---

*Compliance Dashboard v1.0.2*
