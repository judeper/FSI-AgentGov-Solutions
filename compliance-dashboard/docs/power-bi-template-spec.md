# Power BI Template Specification

Complete instructions for manually creating the ComplianceDashboard.pbit Power BI template file using Power BI Desktop.

---

## Overview

The Compliance Dashboard Power BI template (.pbit file) must be created manually using Power BI Desktop GUI, as template creation cannot be fully automated. This document provides step-by-step instructions to build the template from scratch.

**Template Purpose:**
- Provides parameterized Dataverse connection for multi-tenant deployment
- Includes pre-configured data model with relationships and DAX measures
- Contains all 5 dashboard pages with visuals and formatting
- Enables customers to deploy without Power BI development skills

**Time to Create:** Approximately 2-3 hours for first-time creation

---

## Prerequisites

- Power BI Desktop (latest version) - [Download here](https://powerbi.microsoft.com/desktop/)
- Access to Dataverse environment with deployed Compliance Dashboard tables
- Sample data loaded (recommended for testing visuals)
- Familiarity with Power BI Desktop interface

---

## Step 1: Create New Report

1. Open Power BI Desktop
2. Click **File** > **New** to create blank report
3. Save immediately as `ComplianceDashboard.pbix` (working file)

---

## Step 2: Configure Parameters

Parameters allow customers to enter their own Dataverse environment URL and tenant ID at deployment time.

1. Click **Home** > **Transform data** > **Manage Parameters**
2. Click **New Parameter**

### Parameter 1: DataverseEnvironmentUrl

| Setting | Value |
|---------|-------|
| Name | `DataverseEnvironmentUrl` |
| Description | `Your Dataverse environment URL (e.g., https://contoso.crm.dynamics.com)` |
| Required | `Yes` (checked) |
| Type | `Text` |
| Suggested Values | `Any value` |
| Default value | `https://your-org.crm.dynamics.com` |
| Current value | (use your test environment URL) |

3. Click **OK**

### Parameter 2: TenantId

1. Click **New Parameter** again

| Setting | Value |
|---------|-------|
| Name | `TenantId` |
| Description | `Your Azure AD tenant ID (GUID format)` |
| Required | `Yes` (checked) |
| Type | `Text` |
| Suggested Values | `Any value` |
| Default value | `12345678-1234-1234-1234-123456789abc` |
| Current value | (use your actual tenant ID for testing) |

2. Click **OK**
3. Click **Close** to exit parameter manager

---

## Step 3: Connect to Dataverse

### Add Dataverse Data Source

1. Click **Home** > **Get Data** > **More**
2. Search for "Dataverse"
3. Select **Dataverse**
4. Click **Connect**

### Configure Connection

1. In the "Server URL" field, delete the placeholder
2. Click **fx** button next to the field to use a formula
3. Enter: `DataverseEnvironmentUrl`
4. Click **OK**
5. Select **Import** mode (not DirectQuery)
6. Click **OK**

### Authenticate

1. Sign in with organizational account
2. Select **Organizational account** tab
3. Click **Sign in**
4. Complete authentication
5. Click **Connect**

### Select Tables

In the Navigator window, select these tables (check the box next to each):

- [ ] `fsi_controlmaster`
- [ ] `fsi_controlassessment`
- [ ] `fsi_compliancescore`
- [ ] `fsi_complianceexception`
- [ ] `fsi_complianceevidence`

**Do not select other tables** (keeps model lightweight)

Click **Load** (not Transform Data)

### Rename Tables

In the **Data** pane on the right, right-click each table and select **Rename**:

| Original Name | New Name |
|---------------|----------|
| `fsi_controlmaster` | `ControlMaster` |
| `fsi_controlassessment` | `ControlAssessment` |
| `fsi_compliancescore` | `ComplianceScore` |
| `fsi_complianceexception` | `ComplianceException` |
| `fsi_complianceevidence` | `ComplianceEvidence` |

---

## Step 4: Create Date Table

A date table is required for time intelligence functions.

1. Click **Modeling** tab > **New Table**
2. In the formula bar, enter:

```dax
DateTable =
ADDCOLUMNS(
    CALENDAR(DATE(2025, 1, 1), DATE(2027, 12, 31)),
    "Year", YEAR([Date]),
    "Month", MONTH([Date]),
    "MonthName", FORMAT([Date], "MMMM"),
    "Quarter", "Q" & QUARTER([Date]),
    "QuarterName", "Q" & QUARTER([Date]) & " " & YEAR([Date]),
    "WeekNum", WEEKNUM([Date]),
    "DayOfWeek", WEEKDAY([Date]),
    "DayName", FORMAT([Date], "dddd"),
    "IsCurrentMonth", IF(
        MONTH([Date]) = MONTH(TODAY()) && YEAR([Date]) = YEAR(TODAY()),
        TRUE,
        FALSE
    ),
    "IsCurrentYear", IF(YEAR([Date]) = YEAR(TODAY()), TRUE, FALSE)
)
```

3. Press **Enter**
4. Verify table appears in Data pane

### Mark as Date Table

1. Click **Modeling** tab
2. Select **DateTable** in Data pane
3. Click **Mark as date table** > **Mark as date table**
4. In dialog, select **Date** column
5. Click **OK**

---

## Step 5: Configure Relationships

### View Relationship Diagram

1. Click **Model** view (icon on left sidebar)
2. Verify tables appear in diagram
3. Drag tables to organize visually

### Create Relationships

Power BI may auto-detect some relationships. Verify and create the following:

#### Relationship 1: DateTable to ComplianceScore

1. Drag `DateTable[Date]` to `ComplianceScore[fsi_scoredate]`
2. Verify relationship settings:
   - Cardinality: **One to many (1:*)**
   - Cross filter direction: **Single**
   - Make this relationship active: **Checked**
3. Click **OK**

#### Relationship 2: ControlMaster to ControlAssessment

1. Drag `ControlMaster[fsi_controlmasterid]` to `ControlAssessment[fsi_controlmasterid]`
2. Verify relationship settings:
   - Cardinality: **One to many (1:*)**
   - Cross filter direction: **Single**
   - Make this relationship active: **Checked**
3. Click **OK**

#### Relationship 3: ControlAssessment to ComplianceException

1. Drag `ControlAssessment[fsi_controlassessmentid]` to `ComplianceException[fsi_controlassessmentid]`
2. Verify relationship settings:
   - Cardinality: **One to many (1:*)**
   - Cross filter direction: **Single**
   - Make this relationship active: **Checked**
3. Click **OK**

#### Relationship 4: ControlAssessment to ComplianceEvidence

1. Drag `ControlAssessment[fsi_controlassessmentid]` to `ComplianceEvidence[fsi_controlassessmentid]`
2. Verify relationship settings:
   - Cardinality: **One to many (1:*)**
   - Cross filter direction: **Single**
   - Make this relationship active: **Checked**
3. Click **OK**

---

## Step 6: Create DAX Measures

All measures should be created in a single **Measures** table for organization.

### Create Measures Table

1. Click **Home** > **Enter Data**
2. Delete default columns (click **X** on column headers)
3. Name table: `Measures`
4. Click **Load**

### Add Measures

For each measure below, select the **Measures** table in Data pane, then:
1. Click **Modeling** > **New Measure**
2. Paste the DAX code
3. Press **Enter**

See [dax-measures.md](dax-measures.md) for complete measure library. Key measures to create:

#### Overall Score

```dax
Overall Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_overallscore]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )
```

#### Pillar Scores

```dax
Pillar 1 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_pillar1score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )

Pillar 2 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_pillar2score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )

Pillar 3 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_pillar3score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )

Pillar 4 Score =
VAR LatestDate = MAX(ComplianceScore[fsi_scoredate])
RETURN
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_pillar4score]),
        ComplianceScore[fsi_scoredate] = LatestDate
    )
```

#### Score Trend Measures

```dax
Score Change 30D =
VAR CurrentScore = [Overall Score]
VAR PriorDate = MAX(ComplianceScore[fsi_scoredate]) - 30
VAR PriorScore =
    CALCULATE(
        AVERAGE(ComplianceScore[fsi_overallscore]),
        ComplianceScore[fsi_scoredate] = PriorDate
    )
RETURN
    CurrentScore - PriorScore

Score Trend Direction =
VAR Change = [Score Change 30D]
RETURN
    SWITCH(
        TRUE(),
        Change > 2, "Improving",
        Change < -2, "Declining",
        "Stable"
    )
```

#### Control Status Measures

```dax
Total Controls = COUNTROWS(ControlMaster)

Compliant Controls =
CALCULATE(
    COUNTROWS(ControlAssessment),
    ControlAssessment[fsi_status] = 1
)

Partial Controls =
CALCULATE(
    COUNTROWS(ControlAssessment),
    ControlAssessment[fsi_status] = 2
)

Non-Compliant Controls =
CALCULATE(
    COUNTROWS(ControlAssessment),
    ControlAssessment[fsi_status] = 3
)
```

#### Exception Measures

```dax
Open Exceptions =
CALCULATE(
    COUNTROWS(ComplianceException),
    ComplianceException[fsi_status] IN {1, 2, 3}
)

Critical Exceptions =
CALCULATE(
    COUNTROWS(ComplianceException),
    ComplianceException[fsi_severity] = 1,
    ComplianceException[fsi_status] IN {1, 2, 3}
)

SLA Compliance % =
VAR OnTrack =
    CALCULATE(
        COUNTROWS(ComplianceException),
        ComplianceException[fsi_slastatus] = 1,
        ComplianceException[fsi_status] IN {1, 2, 3}
    )
VAR Total = [Open Exceptions]
RETURN
    DIVIDE(OnTrack, Total, 1)
```

**Note:** Create all measures from [dax-measures.md](dax-measures.md) for full functionality. The above are minimum required measures.

---

## Step 7: Create Report Pages

Switch to **Report** view (icon on left sidebar).

### Page 1: Executive Summary

1. Rename page: Right-click **Page 1** > **Rename** > `Executive Summary`

#### Visual 1: Overall Score Card

1. Click **Visualizations** pane > **Card** visual
2. Drag to top-left corner, resize to ~300x200px
3. Add field: Drag `[Overall Score]` from Measures to **Fields**
4. Format:
   - Click **Format** (paint roller icon)
   - **Callout value** > Font size: `48`
   - **Callout value** > Color: `#0078D4` (blue)
   - **Category label** > Text: `Overall Compliance Score`
   - **Category label** > Font size: `14`

#### Visual 2: Score Trend Line Chart

1. Add **Line chart** visual
2. Position: Top-center, ~500x200px
3. Fields:
   - **X-axis:** `DateTable[Date]`
   - **Y-axis:** `ComplianceScore[fsi_overallscore]`
4. Format:
   - **X-axis** > Type: `Continuous`
   - **Y-axis** > Range: `0` to `100`
   - **Data labels:** Off
   - **Title** > Text: `30-Day Compliance Trend`

#### Visual 3: Pillar Scores Column Chart

1. Add **Clustered column chart** visual
2. Position: Top-right, ~400x200px
3. Fields:
   - **X-axis:** Create calculated column in Measures:
     ```dax
     Pillar Names = {"Security", "Management", "Reporting", "SharePoint"}
     ```
   - **Y-axis:** `[Pillar 1 Score]`, `[Pillar 2 Score]`, `[Pillar 3 Score]`, `[Pillar 4 Score]`
4. Format:
   - **Data colors:** Blue gradient
   - **Title** > Text: `Compliance by Pillar`

#### Visual 4: Exception Count Card

1. Add **Card** visual
2. Position: Middle-left, ~250x150px
3. Field: `[Open Exceptions]`
4. Format:
   - **Callout value** > Font size: `36`
   - **Callout value** > Color: `#D13438` (red)
   - **Category label** > Text: `Open Exceptions`

#### Visual 5: SLA Status Stacked Bar Chart

1. Add **Stacked bar chart** visual
2. Position: Middle-center, ~400x150px
3. Fields:
   - **Axis:** `ComplianceException[fsi_slastatus]`
   - **Values:** `COUNTROWS(ComplianceException)`
4. Format:
   - **Data colors:** Green (On Track), Yellow (At Risk), Red (Breached)
   - **Title** > Text: `Exception SLA Status`

#### Visual 6: Zone Distribution Donut Chart

1. Add **Donut chart** visual
2. Position: Bottom-right, ~300x250px
3. Fields:
   - **Legend:** `ControlAssessment[fsi_zone]`
   - **Values:** `COUNTROWS(ControlAssessment)`
4. Format:
   - **Detail labels:** Percentage
   - **Title** > Text: `Assessment Distribution by Zone`

---

### Page 2: Pillar Overview

1. Add new page, rename to `Pillar Overview`

#### Visual 1: Pillar Score Cards (Multi-row card)

1. Add **Multi-row card** visual
2. Position: Left side, ~300x400px
3. Fields:
   - Add `[Pillar 1 Score]`, `[Pillar 2 Score]`, `[Pillar 3 Score]`, `[Pillar 4 Score]`
4. Format:
   - **Card title** > Text: `Pillar Scores`
   - **Data labels** > Font size: `24`

#### Visual 2: Control Status Matrix

1. Add **Matrix** visual
2. Position: Center, ~600x400px
3. Fields:
   - **Rows:** `ControlMaster[fsi_pillar]`
   - **Columns:** `ControlAssessment[fsi_status]`
   - **Values:** `COUNTROWS(ControlAssessment)`
4. Format:
   - **Conditional formatting** on Values:
     - Apply color scale: White (0) to Green (max)
   - **Title** > Text: `Controls by Pillar and Status`

#### Visual 3: Pillar Trend Line Chart

1. Add **Line chart** visual
2. Position: Top-right, ~400x300px
3. Fields:
   - **X-axis:** `DateTable[Date]`
   - **Y-axis:** `[Pillar 1 Score]`, `[Pillar 2 Score]`, `[Pillar 3 Score]`, `[Pillar 4 Score]`
   - **Legend:** Will auto-populate with measure names
4. Format:
   - **X-axis** > Type: `Continuous`
   - **Y-axis** > Range: `0` to `100`
   - **Title** > Text: `Pillar Trends Over Time`

#### Visual 4: Non-Compliant Controls Table

1. Add **Table** visual
2. Position: Bottom, ~800x200px
3. Fields:
   - `ControlMaster[fsi_controlid]`
   - `ControlMaster[fsi_name]`
   - `ControlAssessment[fsi_status]`
4. Filter: `ControlAssessment[fsi_status]` = 3 (Non-Compliant)
5. Format:
   - **Title** > Text: `Non-Compliant Controls`

---

### Page 3: Control Details

1. Add new page, rename to `Control Details`

#### Visual 1: Control List Table

1. Add **Table** visual
2. Position: Left side, ~500x600px
3. Fields:
   - `ControlMaster[fsi_controlid]`
   - `ControlMaster[fsi_name]`
   - `ControlMaster[fsi_pillar]`
   - `ControlAssessment[fsi_status]`
   - `ControlAssessment[fsi_zone]`
   - `ControlAssessment[fsi_assessmentdate]`
4. Format:
   - **Conditional formatting** on `fsi_status`:
     - Apply background color rules
   - **Title** > Text: `Control Inventory`

#### Visual 2: Assessment History Line Chart

1. Add **Line chart** visual
2. Position: Top-right, ~500x300px
3. Fields:
   - **X-axis:** `ControlAssessment[fsi_assessmentdate]`
   - **Y-axis:** `ControlAssessment[fsi_score]`
4. Format:
   - **Y-axis** > Range: `0` to `100`
   - **Title** > Text: `Selected Control History`
5. Enable **Drill-through:** from Control List table

#### Visual 3: Evidence List Table

1. Add **Table** visual
2. Position: Bottom-right, ~500x250px
3. Fields:
   - `ComplianceEvidence[fsi_name]`
   - `ComplianceEvidence[fsi_evidencetype]`
   - `ComplianceEvidence[fsi_collecteddate]`
   - `ComplianceEvidence[fsi_collectedby]`
4. Format:
   - **Title** > Text: `Evidence Items`

#### Visual 4: Regulatory Tags Slicer

1. Add **Slicer** visual
2. Position: Top-left, ~200x300px
3. Field: `ControlMaster[fsi_regulatoryreference]`
4. Format:
   - **Slicer settings** > Style: `List`
   - **Title** > Text: `Filter by Regulation`

---

### Page 4: Exception Tracker

1. Add new page, rename to `Exception Tracker`

#### Visual 1: Open Exceptions Card

1. Add **Card** visual
2. Position: Top-left, ~200x150px
3. Field: `[Open Exceptions]`
4. Format:
   - **Callout value** > Font size: `48`
   - **Category label** > Text: `Open Exceptions`

#### Visual 2: SLA Distribution Pie Chart

1. Add **Pie chart** visual
2. Position: Top-center, ~300x300px
3. Fields:
   - **Legend:** `ComplianceException[fsi_slastatus]`
   - **Values:** `COUNTROWS(ComplianceException)`
4. Format:
   - **Data colors:** Green (On Track), Yellow (At Risk), Red (Breached)
   - **Detail labels:** Category and percentage
   - **Title** > Text: `SLA Status Distribution`

#### Visual 3: Exception Table

1. Add **Table** visual
2. Position: Center, ~900x400px
3. Fields:
   - `ComplianceException[fsi_name]`
   - `ComplianceException[fsi_severity]`
   - `ComplianceException[fsi_status]`
   - `ComplianceException[fsi_owner]`
   - `ComplianceException[fsi_daysopen]`
   - `ComplianceException[fsi_targetdate]`
   - `ComplianceException[fsi_slastatus]`
4. Format:
   - **Conditional formatting** on `fsi_slastatus` column
   - **Title** > Text: `Exception Details`

#### Visual 4: Age Distribution Histogram

1. Add **Column chart** visual
2. Position: Bottom-left, ~400x250px
3. Fields:
   - **X-axis:** `ComplianceException[fsi_daysopen]` (binned)
   - **Y-axis:** `COUNTROWS(ComplianceException)`
4. Format:
   - **X-axis** > Type: `Continuous`
   - **Title** > Text: `Days Open Distribution`

#### Visual 5: Owner Workload Bar Chart

1. Add **Bar chart** visual
2. Position: Bottom-right, ~400x250px
3. Fields:
   - **Axis:** `ComplianceException[fsi_owner]`
   - **Values:** `COUNTROWS(ComplianceException)`
4. Format:
   - **Data labels:** On
   - **Title** > Text: `Exceptions per Owner`

---

### Page 5: Trend Analysis

1. Add new page, rename to `Trend Analysis`

#### Visual 1: Overall Score Trend with Forecast

1. Add **Line chart** visual
2. Position: Top, ~1000x350px
3. Fields:
   - **X-axis:** `DateTable[Date]`
   - **Y-axis:** `ComplianceScore[fsi_overallscore]`
4. **Enable Analytics:**
   - Click visual, expand **Analytics** pane (graph icon)
   - Click **Forecast** > **Add**
   - Set forecast length: `30` days
   - Confidence interval: `95%`
5. Format:
   - **X-axis** > Type: `Continuous`
   - **Y-axis** > Range: `0` to `100`
   - **Title** > Text: `90-Day Compliance Trend with 30-Day Forecast`

#### Visual 2: Pillar Trends Multi-Line Chart

1. Add **Line chart** visual
2. Position: Middle-left, ~500x300px
3. Fields:
   - **X-axis:** `DateTable[Date]`
   - **Y-axis:** `[Pillar 1 Score]`, `[Pillar 2 Score]`, `[Pillar 3 Score]`, `[Pillar 4 Score]`
   - **Legend:** Auto-populated with pillar names
4. Format:
   - **Data colors:** Assign unique color per pillar
   - **Title** > Text: `Pillar Comparison Over Time`

#### Visual 3: Month-over-Month Change KPI

1. Add **KPI** visual
2. Position: Top-right, ~300x200px
3. Fields:
   - **Indicator:** `[Overall Score]`
   - **Trend axis:** `DateTable[MonthName]`
   - **Target goals:** `[Overall Score]` (previous month)
4. Format:
   - **Trend axis** > Direction: `High is good`
   - **Title** > Text: `Month-over-Month Change`

#### Visual 4: Control Status Changes Waterfall

1. Add **Waterfall chart** visual
2. Position: Bottom, ~800x300px
3. Fields:
   - **Category:** Create measure for status transitions
   - **Y-axis:** Count of controls changing status
4. Format:
   - **Data colors:** Increase (Green), Decrease (Red)
   - **Title** > Text: `Control Status Transitions`

---

## Step 8: Apply Theme

### Option A: Use Built-in Theme

1. Click **View** > **Themes**
2. Select a neutral professional theme:
   - **Recommended:** "Executive" or "Accessible"
3. Theme applies to all pages

### Option B: Create Custom Theme (Advanced)

1. Create JSON theme file:

```json
{
  "name": "FSI Compliance Dashboard",
  "dataColors": [
    "#0078D4",
    "#107C10",
    "#FFB900",
    "#D13438",
    "#8764B8",
    "#00B7C3"
  ],
  "background": "#FFFFFF",
  "foreground": "#252423",
  "tableAccent": "#0078D4",
  "good": "#107C10",
  "neutral": "#FFB900",
  "bad": "#D13438"
}
```

2. Save as `ComplianceDashboardTheme.json`
3. In Power BI Desktop: **View** > **Themes** > **Browse for themes**
4. Select JSON file
5. Click **Open**

---

## Step 9: Configure Row-Level Security (Documentation Only)

**Important:** RLS roles are NOT pre-configured in the template. Customers must create roles matching their organizational structure after deployment.

### Example RLS Roles (for customer reference)

Include these examples in template documentation, but do NOT implement:

#### Example Role 1: Zone Viewer

Restricts users to see only data from specific zones.

```dax
[fsi_zone] = VALUE(USERPRINCIPALNAME())
```

**Note to customers:** Replace with actual zone assignment logic from your identity system.

#### Example Role 2: Pillar Owner

Restricts users to see only data from specific pillars.

```dax
[fsi_pillar] IN {
    IF(USERPRINCIPALNAME() = "security@contoso.com", 1),
    IF(USERPRINCIPALNAME() = "management@contoso.com", 2),
    IF(USERPRINCIPALNAME() = "reporting@contoso.com", 3),
    IF(USERPRINCIPALNAME() = "sharepoint@contoso.com", 4)
}
```

**Note to customers:** Customize based on your role assignment approach.

### RLS Implementation Steps (for customers)

Provide these instructions in the template:

1. Open report in Power BI Desktop
2. Click **Modeling** > **Manage roles**
3. Create roles with DAX filters matching your org structure
4. Test roles using **View as** feature
5. Publish report to Power BI Service
6. Assign users to roles in workspace settings

---

## Step 10: Export Power BI Template

### Save Working Copy First

1. Click **File** > **Save**
2. Save as `ComplianceDashboard.pbix` (working copy for testing)

### Export as Template

1. Click **File** > **Export** > **Power BI template**
2. Dialog appears: "Create Power BI Template"
3. Enter description:
   ```
   Compliance Dashboard for FSI Agent Governance Framework v1.0.0

   Provides aggregated compliance reporting across all 62 controls with zone-based filtering.

   Required parameters:
   - DataverseEnvironmentUrl: Your Dataverse environment URL
   - TenantId: Your Azure AD tenant ID

   For deployment instructions, see: docs/deployment-checklist.md
   ```
4. Check **Include sample data in the template:** `No` (unchecked)
   - Ensures template is lightweight
   - Customers connect to their own environment
5. Click **OK**
6. Save as: `ComplianceDashboard.pbit`
7. Location: `/templates/` directory in solution repository

### Verify Template Export

1. Close Power BI Desktop
2. Navigate to `/templates/` directory
3. Verify `ComplianceDashboard.pbit` file exists
4. Check file size (should be <5 MB without sample data)

### Test Template Deployment

1. Open `ComplianceDashboard.pbit` in Power BI Desktop
2. Template prompts for parameters
3. Enter test environment URL and tenant ID
4. Verify data loads successfully
5. Verify all 5 pages render correctly
6. Verify measures calculate properly

---

## Validation Checklist

Before finalizing template, verify:

- [ ] Both parameters (DataverseEnvironmentUrl, TenantId) are configured
- [ ] All 5 Dataverse tables connected and renamed
- [ ] DateTable created with correct DAX
- [ ] DateTable marked as date table
- [ ] All 4 relationships created and active
- [ ] Measures table created with all DAX measures
- [ ] All 5 report pages created and named correctly
- [ ] Each page has all required visuals
- [ ] Theme applied (neutral professional colors)
- [ ] RLS documented but NOT implemented
- [ ] Template exports successfully as .pbit
- [ ] Template file size < 5 MB
- [ ] Test deployment loads data successfully
- [ ] All visuals render without errors

---

## Troubleshooting Template Creation

| Issue | Cause | Resolution |
|-------|-------|------------|
| Parameter not prompting | Parameter not used in connection | Verify connection uses `DataverseEnvironmentUrl` formula |
| Tables won't load | Authentication failed | Re-authenticate with valid organizational account |
| Relationships auto-created wrong | Power BI guessed incorrectly | Delete auto relationships, create manually |
| Measures show errors | Missing relationship or table | Verify DateTable relationship to ComplianceScore exists |
| Theme won't apply | JSON syntax error | Validate JSON with linter |
| Export fails | Sample data too large | Clear data cache before export |
| Template prompts for credentials | Data source settings stored | Remove saved credentials before export |

---

## Maintenance Notes

### When to Update Template

Update the .pbit template when:

- New DAX measures added to measure library
- Dashboard page layout significantly improved
- New visuals added that provide value
- Dataverse schema changes (new tables/columns)

### Version Control

- Store both `.pbix` (working file) and `.pbit` (template) in repository
- Tag template releases: `compliance-dashboard-v1.0.0`
- Document template changes in CHANGELOG.md

---

## Additional Resources

- **DAX Measure Library:** See [dax-measures.md](dax-measures.md) for complete measure definitions
- **Power BI Setup Guide:** See [power-bi-setup.md](power-bi-setup.md) for deployment instructions
- **Dataverse Schema:** See [dataverse-schema.md](dataverse-schema.md) for table structure
- **Deployment Checklist:** See [deployment-checklist.md](deployment-checklist.md) for validation steps

---

*Compliance Dashboard v1.0.0 - Power BI Template Specification*
