# Agent Lifecycle Admin Portal — Build Guide

## Overview

A canvas app for the governance team to manage agent lifecycle operations. This is NOT an exported app — build it manually in Power Apps Studio following the instructions below.

> **Note:** This guide describes how to construct the app from scratch. No Power Apps package is included in this solution.

## Data Sources

Connect to the following Dataverse tables:

| Table | Logical Name | Purpose |
|-------|-------------|---------|
| Agent Lifecycle Record | `fsi_agentlifecyclerecord` | Master lifecycle state |
| Sponsor Assignment | `fsi_sponsorassignment` | Sponsor history |
| Access Review | `fsi_accessreview` | Access review records |
| Deactivation Request | `fsi_deactivationrequest` | Deactivation approvals |
| Lifecycle Compliance Event | `fsi_lifecyclecomplianceevent` | Compliance event log |

### Adding Data Sources

1. Open Power Apps Studio
2. Select **Data** from the left panel
3. Click **Add data** → **Dataverse**
4. Search for and select each table listed above
5. Verify all five tables appear in the Data panel

## Screens

### Screen 1: Agent Dashboard

**Purpose:** Overview of all agent lifecycle records with filtering and status indicators.

**Components:**

- **Gallery** showing all agents from `fsi_agentlifecyclerecord`
- **Filter controls:**
  - Dropdown: Governance Zone (Zone 1 / Zone 2 / Zone 3)
  - Dropdown: Lifecycle Stage (Onboarding / Active / Under Review / Inactive / Deactivated / Deleted)
  - Dropdown: Access Review Status (Pending / In Progress / Completed / Overdue / Escalated)
- **Gallery columns:** Agent Name, Zone, Stage, Sponsor, Inactivity Days, Next Review Due
- **Color coding:**
  - Green: Active
  - Yellow: Under Review / Inactive
  - Red: Pending Deactivation

**Gallery formula example:**

```
SortByColumns(
    Filter(
        fsi_agentlifecyclerecords,
        (IsBlank(ddZone.Selected.Value) || fsi_governancezone = ddZone.Selected.Value),
        (IsBlank(ddStage.Selected.Value) || fsi_lifecyclestage = ddStage.Selected.Value)
    ),
    "fsi_agentname",
    SortOrder.Ascending
)
```

### Screen 2: Agent Detail

**Purpose:** Full lifecycle view for a selected agent with history and actions.

**Components:**

- **Display form** showing the full lifecycle record for the selected agent
- **Sponsor history gallery** — filtered `fsi_sponsorassignment` records for the selected agent, sorted by `fsi_assignmentdate` descending
- **Access review history gallery** — filtered `fsi_accessreview` records for the selected agent
- **Deactivation request history** — filtered `fsi_deactivationrequest` records
- **Button: "Request Manual Deactivation"** — navigates to a deactivation request form or triggers Flow 4

**Navigation:** Set `OnSelect` of gallery items on Screen 1 to navigate here with context:

```
Navigate(scrAgentDetail, ScreenTransition.None, { selectedAgent: ThisItem })
```

### Screen 3: Compliance Events

**Purpose:** Audit trail of all compliance events for regulatory review.

**Components:**

- **Gallery** showing recent events from `fsi_lifecyclecomplianceevent`
- **Filter controls:**
  - Dropdown: Event Type
  - Dropdown: Compliance Impact (Informational / Low / Medium / High / Critical)
  - Date picker: Date Range (start/end)
- **Export functionality:** Button to export filtered gallery data to CSV

**Export formula example:**

```
// Use a collection to stage data, then export
ClearCollect(colExport, Filter(fsi_lifecyclecomplianceevents, ...));
```

> **Note:** Canvas app CSV export requires a Power Automate flow or the `Download` function. See Power Apps documentation for current export options.

### Screen 4: Sponsor Management

**Purpose:** Monitor sponsor coverage and manage reassignments.

**Components:**

- **Gallery** of current sponsor assignments where `fsi_iscurrent = true`
- **Highlight indicator** for agents with inactive sponsors (`fsi_sponsoractive = false`)
- **Button: "Reassign Sponsor"** — opens an edit form to update the sponsor assignment
- **Sponsor coverage metric** — count of agents with active sponsors vs. total

## Security

### App Sharing

- Share the app with the governance team security group only
- Do not share with all users in the organization
- Use Dataverse security roles to restrict row-level access where applicable

### Data Access

- Use Dataverse row-level security to restrict access by business unit or zone
- Audit all app interactions via Dataverse audit logging
- Do not store sensitive data in app-level variables or collections

### Connection Context

- The app runs in the context of the signed-in user's Dataverse permissions
- Verify that governance team members have appropriate Dataverse security roles

## Design Recommendations

| Setting | Recommendation |
|---------|---------------|
| **Theme** | Use organization branding colors |
| **Layout** | Responsive layout for tablet and desktop |
| **Loading** | Add loading spinners for gallery data refresh |
| **Error handling** | Display user-friendly error messages for failed operations |

---

*Agent 365 Lifecycle Governance v1.0.0*
