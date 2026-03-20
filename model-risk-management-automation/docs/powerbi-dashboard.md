# MRM Compliance Dashboard — Power BI Build Guide

## Overview

Examiner-ready dashboard for model inventory status, validation coverage, risk distribution, and monitoring trends. This dashboard supports compliance with Fed SR 11-7 and OCC 2011-12 reporting expectations by providing centralized visibility into MRM program metrics.

> **Note:** This dashboard aids in meeting regulatory reporting requirements. Organizations should verify that dashboard content and refresh cadence meet their specific examination obligations.

## Data Model

Connect to the following Dataverse tables. Use the OData connector in Power BI Desktop with your environment URL.

| Table | Role |
|-------|------|
| `fsi_modelinventory` | Primary — agent model inventory records |
| `fsi_mrmriskrating` | Risk scoring history per agent |
| `fsi_validationcycle` | Validation workflow lifecycle |
| `fsi_validationfinding` | Findings raised during validation |
| `fsi_monitoringrecord` | Scheduled performance monitoring data |
| `fsi_mrmcomplianceevent` | Audit trail of compliance-relevant events |

### Relationships

- `fsi_modelinventory` 1:N → `fsi_mrmriskrating` (on `fsi_modelid`)
- `fsi_modelinventory` 1:N → `fsi_validationcycle` (on `fsi_modelid`)
- `fsi_validationcycle` 1:N → `fsi_validationfinding` (on `fsi_validationcycleid`)
- `fsi_modelinventory` 1:N → `fsi_monitoringrecord` (on `fsi_modelid`)
- `fsi_modelinventory` 1:N → `fsi_mrmcomplianceevent` (on `fsi_modelid`)

## Dashboard Pages

### Page 1: Inventory Overview

| Visual | Type | Description |
|--------|------|-------------|
| Total Agents in MRM Inventory | Card | `COUNTROWS(fsi_modelinventory)` |
| Agents Pending Submission | Card | Count where `fsi_mrmstatus = "Registered"` |
| Agents Validated | Card | Count where `fsi_validationstatus = "Validated"` |
| Agents by MRM Tier | Bar chart | X-axis: `fsi_mrmtier` (Tier 1–4), Y-axis: count |
| Risk Rating Distribution | Pie chart | Segments: Critical, High, Medium, Low from `fsi_currentriskrating` |
| Agent Inventory Detail | Table | Columns: Model ID, Name, Tier, Rating, Status, Next Validation Due |

**Filter bar:** MRM Tier, Risk Rating, Validation Status, Business Function.

### Page 2: Validation Status

| Visual | Type | Description |
|--------|------|-------------|
| Open Validation Cycles | Card | Count where `fsi_cyclestatus` is not Completed or Rejected |
| Overdue Validations | Card | Uses `Overdue Validations` DAX measure (see below) |
| SLA Breaches | Card | Count of cycles where any SLA phase is breached |
| Validation Status by Tier | Stacked bar | X-axis: Tier, segments: cycle status values |
| Validation Cycle Durations | Timeline | Start: `fsi_submitteddate`, End: `fsi_completeddate` |
| Active Cycles Detail | Table | Cycle ID, Model Name, Phase, Assigned Validator, SLA Status, Days Remaining |

### Page 3: Findings & Remediation

| Visual | Type | Description |
|--------|------|-------------|
| Open Critical Findings | Card | Count where severity = Critical and status ≠ Closed |
| Total Open Findings | Card | Count where status ≠ Closed |
| Findings by Category | Bar chart | X-axis: `fsi_findingcategory`, Y-axis: count |
| Findings by Severity | Bar chart | X-axis: `fsi_findingseverity`, Y-axis: count |
| Open Findings Detail | Table | Finding ID, Model Name, Category, Severity, Owner, Due Date, Status |

### Page 4: Monitoring Trends

| Visual | Type | Description |
|--------|------|-------------|
| Error Rate Trends | Line chart | X-axis: week, Y-axis: error rate, series: agent name |
| Escalation Rate Trends | Line chart | X-axis: week, Y-axis: escalation rate, series: agent name |
| Threshold Breaches This Month | Card | Count of monitoring records with breach flags |
| Recent Monitoring Alerts | Table | Agent Name, Metric, Threshold, Actual Value, Drift Signal, Date |

### Page 5: Compliance Events

| Visual | Type | Description |
|--------|------|-------------|
| Total Events (Last 30 Days) | Card | Filtered count of `fsi_mrmcomplianceevent` |
| Events by Type | Bar chart | X-axis: `fsi_eventtype`, Y-axis: count |
| Events by SR 11-7 Pillar | Pie chart | Segments from `fsi_regulatorypillar` |
| Recent Compliance Events | Table | Event ID, Model Name, Event Type, Impact Level, Date, Details |

## Key DAX Measures

```dax
Agents Not Validated = 
CALCULATE(
    COUNTROWS(fsi_modelinventory),
    fsi_modelinventory[fsi_validationstatus] <> "Validated"
)

Tier 1 Coverage = 
DIVIDE(
    CALCULATE(COUNTROWS(fsi_modelinventory), 
        fsi_modelinventory[fsi_mrmtier] = "Tier 1",
        fsi_modelinventory[fsi_validationstatus] = "Validated"),
    CALCULATE(COUNTROWS(fsi_modelinventory),
        fsi_modelinventory[fsi_mrmtier] = "Tier 1"),
    0
)

Overdue Validations = 
CALCULATE(
    COUNTROWS(fsi_modelinventory),
    fsi_modelinventory[fsi_nextvalidationdue] < TODAY(),
    fsi_modelinventory[fsi_validationstatus] = "Validated"
)

Avg Cycle Duration Days = 
AVERAGEX(
    FILTER(fsi_validationcycle, NOT(ISBLANK(fsi_validationcycle[fsi_completeddate]))),
    DATEDIFF(fsi_validationcycle[fsi_submitteddate], fsi_validationcycle[fsi_completeddate], DAY)
)

Open Critical Findings = 
CALCULATE(
    COUNTROWS(fsi_validationfinding),
    fsi_validationfinding[fsi_findingseverity] = "Critical",
    fsi_validationfinding[fsi_findingstatus] <> "Closed"
)
```

## Refresh Schedule

| Setting | Recommended Value |
|---------|-------------------|
| Refresh frequency | Daily |
| Refresh time | 06:00 AM UTC |
| Rationale | Flow 1 (Inventory Sync) runs at 05:00 AM UTC — scheduling the refresh one hour later helps capture the latest sync results |

> **Implementation note:** Configure scheduled refresh in the Power BI Service workspace settings after publishing. Gateway configuration may be required for on-premises Dataverse environments.

## Row-Level Security (Optional)

For environments where agent owners should see only their own models:

1. Create a role named `AgentOwnerFilter`
2. Add DAX filter on `fsi_modelinventory`: `[fsi_ownerupn] = USERPRINCIPALNAME()`
3. Assign agent owners to this role in Power BI Service
4. MRM team and examiners should not be assigned to this role

## Publication Checklist

- [ ] All five pages render with live data
- [ ] DAX measures return expected values
- [ ] Refresh schedule configured (daily at 06:00 AM UTC)
- [ ] Row-level security configured (if applicable)
- [ ] Dashboard shared with MRM team and governance stakeholders
- [ ] Document Power BI workspace URL in DELIVERY-CHECKLIST.md
