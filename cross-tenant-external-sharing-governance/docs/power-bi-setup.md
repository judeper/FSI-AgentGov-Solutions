# Power BI: Cross-Tenant Compliance Dashboard

> **Documentation-only** — Build this dashboard manually in Power BI Desktop following these instructions.

## Overview

Dashboard providing cross-tenant compliance posture visibility for governance and examination teams.

## Data Sources

Connect to the Dataverse environment using the Power BI Dataverse connector:

| Table | Purpose |
|-------|---------|
| `fsi_approvedexternaltenants` | Approved tenant registry status |
| `fsi_externalsharefindings` | Open and historical violations |
| `fsi_tenantisolationrecords` | Tenant isolation audit history |
| `fsi_entractarecords` | Entra CTA audit history |
| `fsi_crosstenantcomplianceevents` | Compliance event timeline |

### Connection Steps

1. Open Power BI Desktop
2. Select **Get Data** > **Dataverse**
3. Enter your Dataverse environment URL
4. Authenticate with an account that has read access to the tables above
5. Select the five tables and load them into the model
6. Create relationships between tables using tenant ID and finding ID fields

## Recommended Visuals

### Page 1: Executive Summary

- **KPI Card — Open Violations:** Count of `fsi_externalsharefindings` where status is open, with severity breakdown
- **KPI Card — Approved Tenants:** Count of `fsi_approvedexternaltenants` where approval status is active
- **KPI Card — Overdue Reviews:** Count of approved tenants where `fsi_annualreviewdue < Today()`
- **KPI Card — Compliance Status:** Percentage of external tenants with matching Entra CTA partner policies
- **Donut Chart:** Violation distribution by governance layer (Tenant Isolation, Entra CTA, Agent Sharing)
- **Bar Chart:** Violations by severity (Critical, High, Medium, Low)

### Page 2: Violation Detail

- **Table Visual:** Open findings with columns for severity, governance layer, agent name, external tenant, detection date, and finding type
- **Trend Chart:** Line chart showing new violations per week over the past 90 days
- **Slicer Controls:** Filter by severity, governance layer, zone, and date range
- **Drill-through:** Click a finding row to see full details including remediation steps and assigned owner

### Page 3: Tenant Registry

- **Table Visual:** Approved tenant list with columns for display name, tenant ID, risk tier, relationship type, approval status, and annual review due date
- **Pie Chart:** Risk tier distribution across approved tenants
- **Stacked Bar Chart:** Relationship type breakdown (vendor, partner, acquirer, regulator)
- **Conditional Formatting:** Highlight overdue reviews in red, expiring within 30 days in amber

### Page 4: Audit History

- **Line Chart — Tenant Isolation Trend:** Enabled/Disabled status over time from `fsi_tenantisolationrecords`
- **Line Chart — CTA Compliance Trend:** Percentage of partner policies matching the approved registry over time
- **Timeline Visual:** Compliance events from `fsi_crosstenantcomplianceevents` showing onboarding approvals, remediation actions, and audit completions
- **Date Slicer:** Filter all visuals on this page by date range

## Refresh Schedule

- **Recommended:** Daily refresh aligned with detection flow schedules (Flows 1–3 typically run daily)
- **Configuration:** Publish to Power BI Service and configure a scheduled refresh using a gateway or Dataverse direct connection
- **Incremental Refresh:** Consider configuring incremental refresh on `fsi_externalsharefindings` and `fsi_crosstenantcomplianceevents` tables if data volume exceeds 100,000 rows

## Row-Level Security

- Configure RLS in Power BI Desktop to restrict visibility by business unit or zone if required
- Map Power BI workspace roles to the governance team security group
- Examination teams should receive read-only viewer access to the published dashboard
