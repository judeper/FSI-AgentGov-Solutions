# Power Apps: External Tenant Registry Portal

> **Documentation-only** — Build this Canvas app manually in Power Apps Studio following these instructions.

## Overview

4-screen Canvas app for the governance team to manage approved external tenants and review cross-tenant violations.

## Screen 1: Approved Tenant Registry

### Data Source

- Entity: `fsi_approvedexternaltenants` (confirm entity set name post-deployment)

### Layout

- Gallery control displaying all `fsi_approvedexternaltenant` records
- Filter controls: Approval Status, Risk Tier, Relationship Type, Annual Review Due
- "New Request" button: triggers Flow 4 (External Tenant Onboarding)

### Alert Banners

1. **Overdue annual reviews:** `Filter(fsi_approvedexternaltenants, fsi_annualreviewdue < Today() && fsi_approvalstatus = 1)`
2. **Expiring within 30 days:** `Filter(fsi_approvedexternaltenants, fsi_annualreviewdue <= Today() + 30 && fsi_annualreviewdue > Today() && fsi_approvalstatus = 1)`
3. **Expired onboarding requests:** `Filter(fsi_approvedexternaltenants, fsi_approvalstatus = 2)` — governance team can review and decide to resubmit or close

### Detail View

- Full approval history and associated findings per record
- Tap a row in the gallery to navigate to a detail form showing:
  - Tenant display name, tenant ID, relationship type
  - Current approval status and risk tier
  - Annual review due date and last review date
  - Business justification and sponsoring business unit
  - Associated `fsi_externalsharefindings` records linked to this tenant

## Screen 2: Open Violations

### Data Source

- Entity: `fsi_externalsharefindings` filtered to open status

### Layout

- Gallery grouped by governance layer (Tenant Isolation, Entra CTA, Agent Sharing)
- Each row shows: Agent name, external tenant, severity, detection date, finding type
- Action buttons per finding:
  - **Remediate** — triggers Flow 5 (Auto-Remediation) for the selected finding
  - **Assign** — opens a panel to assign the finding to a team member for manual review
  - **Export** — generates a CSV of selected findings for audit documentation

### Filtering

- Filter by severity (Critical, High, Medium, Low)
- Filter by governance layer
- Filter by zone classification
- Date range filter for detection date

## Screen 3: Tenant Isolation Posture

### Data Source

- Entity: `fsi_tenantisolationrecords` — most recent record

### Layout

- Status card showing current tenant isolation state (Enabled/Disabled)
- Timestamp of last audit
- Chart showing approved vs. unapproved external tenant trend over time
  - Use a line chart with `fsi_tenantisolationrecords` historical data
  - X-axis: audit date, Y-axis: count of approved and unapproved tenants
- Manual refresh button that triggers Flow 1 (Tenant Isolation Audit) on demand

### Conditional Formatting

- Green banner when tenant isolation is enabled
- Red banner with remediation guidance when tenant isolation is disabled

## Screen 4: Entra CTA Settings Posture

### Data Source

- Entity: `fsi_entractarecords` — most recent record

### Layout

- Summary card showing total partner policies and compliance percentage
- Partner policy entries table with columns:
  - Partner tenant ID, display name, inbound/outbound status
  - Registry match status (Approved / Not in Registry / Expired)
  - Last modified date
- Manual refresh button that triggers Flow 3 (Entra CTA Audit) on demand

### Conditional Formatting

- Highlight rows where registry match status is "Not in Registry" in red
- Highlight rows where registry match status is "Expired" in amber

## Connection Setup

1. **Add Dataverse connection** in Power Apps Studio:
   - Data > Add data > Search for "Dataverse"
   - Select the environment where the solution tables were deployed
   - Add all five tables listed in the data sources above

2. **Link to Power Automate flows**:
   - Action > Power Automate > Add flow
   - Connect Flow 1 (Tenant Isolation Audit) to Screen 3 refresh button
   - Connect Flow 3 (Entra CTA Audit) to Screen 4 refresh button
   - Connect Flow 4 (External Tenant Onboarding) to Screen 1 "New Request" button
   - Connect Flow 5 (Auto-Remediation) to Screen 2 "Remediate" button

3. **Set app permissions**:
   - Share the app with the governance team security group
   - Assign Dataverse security roles that grant read access to all five tables
   - Assign write access only to users who should trigger remediation flows
