# Agent Lifecycle Compliance Dashboard — Build Guide

## Overview

A Power BI report for lifecycle compliance monitoring. Connect directly to Dataverse tables to visualize agent lifecycle state, sponsor coverage, access review completion, and deactivation pipeline.

> **Note:** This guide describes how to build the report from scratch in Power BI Desktop. No `.pbix` file is included in this solution.

## Data Source

| Setting | Value |
|---------|-------|
| **Connection type** | Dataverse connector |
| **Authentication** | Organizational account |

### Tables to Import

| Dataverse Table | Logical Name |
|----------------|-------------|
| Agent Lifecycle Record | `fsi_agentlifecyclerecord` |
| Sponsor Assignment | `fsi_sponsorassignment` |
| Access Review | `fsi_accessreview` |
| Deactivation Request | `fsi_deactivationrequest` |
| Lifecycle Compliance Event | `fsi_lifecyclecomplianceevent` |

### Connection Steps

1. Open Power BI Desktop
2. Select **Get Data** → **Dataverse**
3. Enter the environment URL (e.g., `https://org.crm.dynamics.com`)
4. Sign in with an account that has read access to the governance tables
5. Select all five tables listed above
6. Click **Transform Data** to review column types before loading

## Report Pages

### Page 1: Executive Summary

**Purpose:** High-level metrics for leadership reporting.

**Key metrics cards:**

| Metric | Calculation |
|--------|------------|
| Total Agents | Count of `fsi_agentlifecyclerecord` |
| Sponsor Coverage % | Agents with `fsi_sponsoractive = true` ÷ total |
| Review Completion % | Agents with `fsi_accessreviewstatus = Completed` ÷ total eligible |
| Overdue Reviews | Count where `fsi_accessreviewstatus = Overdue` |

**Visuals:**

- Card visuals for each metric
- Bar chart: Inactive Agents by Zone (grouped by `fsi_governancezone`)
- Donut chart: Agents by Lifecycle Stage

### Page 2: Lifecycle Pipeline

**Purpose:** Visualize the flow of agents through lifecycle stages.

**Visuals:**

- Funnel chart: Onboarding → Active → Under Review → Inactive → Deactivated → Deleted
- Drill-through to agent detail (link to filtered table)
- Time-series line chart: Stage transitions per month

**Funnel configuration:**

- Category: `fsi_lifecyclestage`
- Values: Count of agents
- Sort: By stage order (use a custom sort column if needed)

### Page 3: Access Reviews

**Purpose:** Track access review cadence and completion.

**Visuals:**

- Table: Upcoming reviews (next 30 days) by zone — filter by `fsi_nextreviewdue`
- Line chart: Completion rate trend over time
- Table: Overdue escalation list with certifier names and days overdue

### Page 4: Deactivation Pipeline

**Purpose:** Monitor the deactivation and deletion workflow.

**Visuals:**

- Stacked bar chart: Active deactivation requests by status (Pending / Approved / Rejected)
- Timeline: Deletion hold agents approaching hold expiry (`fsi_deletionholduntil`)
- Bar chart: Deletion history by month (count of agents moved to Deleted stage)

### Page 5: Compliance Events

**Purpose:** Detailed compliance event analysis for audit purposes.

**Visuals:**

- Scatter/timeline visual: Events over time
- Pie chart: Impact distribution by compliance impact level
- Table: Event detail with filters for event type, zone, and date range

## Key Measures (DAX)

```dax
Sponsor Coverage % = 
DIVIDE(
    COUNTROWS(
        FILTER(
            fsi_agentlifecyclerecord,
            fsi_agentlifecyclerecord[fsi_sponsoractive] = TRUE()
        )
    ),
    COUNTROWS(fsi_agentlifecyclerecord),
    0
)

Review Completion % =
DIVIDE(
    COUNTROWS(
        FILTER(
            fsi_agentlifecyclerecord,
            fsi_agentlifecyclerecord[fsi_accessreviewstatus] = "Completed"
        )
    ),
    COUNTROWS(
        FILTER(
            fsi_agentlifecyclerecord,
            fsi_agentlifecyclerecord[fsi_lifecyclestage] = "Active"
        )
    ),
    0
)

Overdue Review Count =
COUNTROWS(
    FILTER(
        fsi_agentlifecyclerecord,
        fsi_agentlifecyclerecord[fsi_accessreviewstatus] = "Overdue"
    )
)

Inactive Agent Count =
COUNTROWS(
    FILTER(
        fsi_agentlifecyclerecord,
        fsi_agentlifecyclerecord[fsi_lifecyclestage] = "Inactive"
    )
)
```

## Refresh Schedule

| Setting | Recommendation |
|---------|---------------|
| **Refresh frequency** | Daily during business hours |
| **Alignment** | Schedule after Flow 3 (Detect-InactiveAgents-Daily) completes |
| **Gateway** | Not required for Dataverse connector (cloud-to-cloud) |
| **Row limit** | Monitor Dataverse query limits for large agent populations |

## Security

### Row-Level Security (RLS)

If zone-based access restriction is required:

1. Create RLS roles in Power BI Desktop (Modeling → Manage Roles)
2. Define DAX filters per zone (e.g., `[fsi_governancezone] = "Zone 3"`)
3. Assign users to roles in Power BI Service after publishing

### Sharing

- Publish to a dedicated governance workspace
- Share with the governance team security group
- Use Power BI Pro or Premium Per User licensing for sharing

---

*Agent 365 Lifecycle Governance v1.1.1*
