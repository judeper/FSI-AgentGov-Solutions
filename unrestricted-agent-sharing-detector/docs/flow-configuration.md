# Flow Configuration Guide

## Overview

This guide provides step-by-step instructions for manually building the Unrestricted Agent Sharing Detector (UASD) Power Automate flows and Canvas app in Power Automate designer.

**Flows to Build:**
1. UASD-Detector-Scan-Agents (Scheduled Cloud Flow)
2. UASD-Remediation-Apply-Sharing-Policy (Automated Cloud Flow)
3. UASD-Exception-Approval-Workflow (Automated Cloud Flow)
4. UASD-Exception-Expiration-Monitor (Scheduled Cloud Flow)
5. UASD-Exception-Manager (Canvas App)

**Prerequisites:**
- Power Automate premium license
- Power Platform Admin role in target environment
- Access to Dataverse and Teams
- Connection references configured (see main deployment guide)

---

## Flow 1: UASD-Detector-Scan-Agents

**Type:** Scheduled Cloud Flow  
**Trigger:** Recurrence (Daily at 06:00 UTC)  
**Purpose:** Scan all Power Platform environments for agent sharing violations

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Scheduled Cloud Flow
   - Flow name: `UASD-Detector-Scan-Agents`
   - Recurrence: Daily at 06:00 UTC

2. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `homeTenantId`: Environment variable `fsi_UASD_HomeTenantId`
   - `dataverseUrl`: Environment variable `fsi_UASD_DataverseUrl`
   - `maxIndividualShares`: Environment variable `fsi_UASD_MaxIndividualShares`
   - `scanFrequencyHours`: Environment variable `fsi_UASD_ScanFrequencyHours` (default: 24; use to configure recurrence interval)

3. **Get Environments** (Power Platform for Admins)
   - Action: "Get Environments as Admin"
   - Filter: Include only non-sandbox environments if desired

4. **For Each Environment**
   - Loop through environments retrieved in step 3

5. **Call Power Platform API** (for each environment)
   - Endpoint: `https://<env-url>/api/data/v9.2/`
   - Method: GET
   - Query agents from Copilot Studio table
   - Parse sharing configuration

6. **Evaluate Violation Rules**
   For each agent, check:
   - **ORG_WIDE_SHARING:** `sharingScope = "organization"`
   - **PUBLIC_INTERNET_LINK:** `publicLinkEnabled = true`
   - **UNAPPROVED_GROUP:** Security groups not in approved registry
   - **EXCESSIVE_INDIVIDUAL:** Individual share count exceeds threshold
   - **CROSS_TENANT_ACCESS:** Allowed tenants include non-home tenant

7. **Create Violation Records** (with deduplication)
   - **Before creating**, check for an existing open violation for the same agent and violation type:
     - Action: "List records" (Dataverse)
     - Table: `fsi_SharingViolation`
     - Filter: `fsi_agentid eq <agent GUID> and fsi_violationtype eq <violation type code> and (fsi_violationstatus eq 100000000 or fsi_violationstatus eq 100000003 or fsi_violationstatus eq 100000004 or fsi_violationstatus eq 100000005 or fsi_violationstatus eq 100000006)`
     - **Condition:** If a matching record exists in any non-resolved state (Open, False Positive, Excluded, Skipped, or Dry Run), skip creation for this violation. This prevents duplicate violation records from accumulating across scan cycles for agents in break-glass exclusion, admin-triaged false positive, dry-run, or skipped remediation states. Only Remediated (100000001) and Exception Approved (100000002) violations allow a new record to be created on re-detection.
   - Action: "Create a new record" (Dataverse)
   - Table: `fsi_SharingViolation`
   - Fields:
     - `fsi_name`: Expression `take(concat(fsi_agentname, ' - ', items('Apply_to_each')?['violation_type']), 100)` (e.g., "Sales Bot - ORG_WIDE_SHARING"). The `take()` function truncates the result to 100 characters to stay within the `fsi_Name` MaxLength constraint. Do not use `substring()` as an alternative — it throws a runtime error when the string is shorter than the specified length.
     - `fsi_agentid`: Agent GUID
     - `fsi_agentname`: Agent display name
     - `fsi_environmentid`: Environment GUID
     - `fsi_violationtype`: Violation type code (100000000–100000004)
     - `fsi_violationstatus`: `100000000` (Open) — must be set explicitly; ApplicationRequired is only enforced at form level, not API level
     - `fsi_severity`: Critical/High/Medium
     - `fsi_description`: Violation details
     - `fsi_evidencejson`: Full sharing config JSON
     - `fsi_detectedat`: Scan timestamp
     - `fsi_scanrunid`: Correlation ID

8. **Send Teams Alert** (if violations found)
   - Action: "Post an Adaptive Card to a Teams Channel"
   - Channel: Use `fsi_UASD_TeamsGroupId` and `fsi_UASD_TeamsChannelId`
   - Card: Summary of violations by severity

9. **Update Agent Settings**
   - Action: "Create or update a record" (Dataverse)
   - Table: `fsi_AgentSharingSetting`
   - Fields: Store point-in-time sharing configuration snapshot

**Trigger Configuration:**
- Frequency: Hour
- Interval: Value of `fsi_UASD_ScanFrequencyHours` (default: 24, i.e., daily)
- Time zone: UTC
- Time: 06:00 (start time for first run)

---

## Flow 2: UASD-Remediation-Apply-Sharing-Policy

**Type:** Automated Cloud Flow  
**Trigger:** When a record is created or updated (Dataverse)  
**Purpose:** Automatically remediate sharing violations using approved security groups

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Automated Cloud Flow
   - Flow name: `UASD-Remediation-Apply-Sharing-Policy`
   - Trigger: "When a record is created or updated"

2. **Configure Trigger**
   - Entity: `fsi_SharingViolation`
   - Message: 1 (Create) and 2 (Update)
   - Scope: 4 (Organization)
   - Filtering attributes: `fsi_violationstatus,fsi_remediatedat` — restricts Update triggers to only fire when these columns change, preventing infinite loops from updates to `fsi_remediationresult` alone
   - Trigger filters:
     - `fsi_violationstatus eq 100000000` (Open violations only)
     - `fsi_remediatedat eq null` (Not yet remediated)

3. **Initialize Dry-Run Mode**
   - Get environment variable: `fsi_UASD_RemediationDryRun`
   - Store in variable `isDryRun`
   - **Note:** `fsi_UASD_RemediationDryRun` is a **String** type environment variable (values `"true"` / `"false"`). Use string comparison in conditions: `equals(variables('isDryRun'), 'true')`, not boolean comparison.
   - Get environment variable: `fsi_UASD_AutoRemediatePublicLink` (default: `"false"`)
   - Store in variable `autoRemediatePublicLink` — when `"true"`, PUBLIC_INTERNET_LINK violations are automatically remediated without manual intervention
   - **Note:** `fsi_UASD_AutoRemediatePublicLink` is also a **String** type. Use string comparison: `equals(variables('autoRemediatePublicLink'), 'true')`.

4. **Get Violation Record Details**
   - Action: "Get a record" (Dataverse)
   - Table: `fsi_SharingViolation`
   - Record ID: Trigger output `fsi_sharingviolationid`

4a. **Check Break-Glass Exclusion**
   - Action: "List records" (Dataverse)
   - Table: `fsi_AgentSharingSetting`
   - Filter: `fsi_agentid eq <violation's fsi_agentid>`
   - **Condition:** If `fsi_breakglassexclude = true`:
     - Update violation record:
       - `fsi_remediationresult`: `"Skipped: break-glass exclusion active"`
       - `fsi_violationstatus`: 100000004 (Excluded) — prevents re-triggering; distinguishes break-glass exclusions from actual false positives
     - Send Teams notification indicating manual review required
     - Terminate flow (do not proceed to remediation)

4b. **Check for Active Exception**
   - Action: "List records" (Dataverse)
   - Table: `fsi_SharingException`
   - Filter: `fsi_agentid eq <violation's fsi_agentid> and fsi_violationtype eq <violation's fsi_violationtype> and fsi_exceptionstatus eq 100000001 and fsi_expiresat gt utcNow()`
   - **Condition:** If an active approved exception exists:
     - Update violation `fsi_violationstatus` to 100000002 (Exception Approved)
     - Update `fsi_remediationresult` to `"Skipped: active exception approved until <fsi_expiresat>"`
     - Terminate flow (do not proceed to remediation)

5. **Get Approved Security Groups for Zone**
   - Action: "List records" (Dataverse)
   - Table: `fsi_ApprovedSecurityGroup`
   - Filter: `fsi_zoneclassification eq <environment-zone> and fsi_isactive eq true`
   - **Zone resolution:** The environment's zone classification must be determined before this step. Zone is not auto-detected; it must be mapped manually. Populate the `fsi_ApprovedSecurityGroup` table with the correct `fsi_zoneclassification` for each environment during Step 5 of deployment (see SOLUTION-DOCUMENTATION.md). The `fsi_SharingPolicy` table is reserved for future per-zone policy enforcement and is not currently used by this flow.

5a. **Guard: Verify Approved Groups Exist**
   - **Condition:** Check `length(body('List_Approved_Groups')?['value'])` is greater than 0
   - **If empty (no approved groups for zone):**
     - Update violation record:
       - `fsi_remediationresult`: `"Skipped: no approved security groups configured for zone <zone>"`
       - `fsi_violationstatus`: 100000005 (Skipped)
     - Send Teams warning: "Remediation skipped — no approved security groups are configured for zone <zone>. Configure approved groups before remediation can proceed."
     - Terminate flow (do not proceed to Step 6)
   - **If groups exist:** Continue to Step 6
   - **Rationale:** Without this guard, ORG_WIDE_SHARING and UNAPPROVED_GROUP remediation would remove existing sharing and add zero groups — effectively revoking all agent access and causing denial of service for legitimate users.

6. **Remediate by Violation Type**
   - Use Switch statement on `fsi_violationtype`:

   **Case 100000000: ORG_WIDE_SHARING**
   - Remove organization-wide sharing
   - Add all approved security groups for zone

   **Case 100000001: PUBLIC_INTERNET_LINK**
   - **Condition:** If `equals(variables('autoRemediatePublicLink'), 'false')`, skip remediation actions — update `fsi_remediationresult` to `"Skipped: autoRemediatePublicLink is disabled"` and `fsi_violationstatus` to `100000005` (Skipped) to prevent re-triggering, then go to step 8
   - Disable public internet link
   - Require Entra ID authentication

   **Case 100000002: UNAPPROVED_GROUP**
   - Remove unapproved security groups
   - Add approved groups (matching zone)

   **Case 100000003: EXCESSIVE_INDIVIDUAL**
   - Remove individual user shares
   - Create/update security group
   - Add group to approved registry

   **Case 100000004: CROSS_TENANT_ACCESS**
   - Remove external tenant access
   - Restrict to home tenant only

7. **Call Agent Sharing API**
   - Endpoint: Copilot Studio agent management
   - Method: PATCH
   - Payload: Updated sharing configuration
   - **Skip if `equals(variables('isDryRun'), 'true')`**

8. **Update Violation Record**
   - **Condition:** Only update remediation status if `equals(variables('isDryRun'), 'false')` and remediation was actually performed
   - **If `equals(variables('isDryRun'), 'true')`:**
     - Action: "Update a record" (Dataverse)
     - Table: `fsi_SharingViolation`
     - Fields:
       - `fsi_remediationresult`: `"Dry-run: no changes applied"` (include planned remediation actions for review)
       - `fsi_violationstatus`: 100000006 (Dry Run) — prevents re-triggering; distinguishes dry-run reviews from actual false positives
     - Do **not** set `fsi_remediatedat` (preserve null to indicate no actual remediation occurred)
   - **If `equals(variables('isDryRun'), 'false')`:**
     - Action: "Update a record" (Dataverse)
     - Table: `fsi_SharingViolation`
     - Fields:
       - `fsi_violationstatus`: 100000001 (Remediated)
       - `fsi_remediatedat`: Current timestamp
       - `fsi_remediationresult`: Success/error message
     - Include operation result

9. **Send Remediation Alert**
   - Action: "Post message in chat or channel" (Teams)
   - Message type: Notification card
   - Include: Agent name, violation type, remediation action
   - Severity color indicator

**Trigger Configuration:**
```
Entity: fsi_SharingViolation
Filtering attributes: fsi_violationstatus,fsi_remediatedat
Trigger filters:
  - fsi_violationstatus eq 100000000
  - fsi_remediatedat eq null
```

**Concurrency Control:**
- In the flow designer, open trigger settings: **Settings → Concurrency Control → On → Degree of Parallelism: 1**
- This ensures serial execution — if the Detector scan creates multiple violations for the same agent simultaneously, remediation runs sequentially to prevent parallel PATCH calls from overwriting each other's sharing API changes.

---

## Flow 3: UASD-Exception-Approval-Workflow

**Type:** Automated Cloud Flow  
**Trigger:** When a record is created (Dataverse)  
**Purpose:** Route exception requests to appropriate approvers based on data classification

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Automated Cloud Flow
   - Flow name: `UASD-Exception-Approval-Workflow`
   - Trigger: "When a record is created"

2. **Configure Trigger**
   - Entity: `fsi_SharingException`
   - Message: 1 (Create only)
   - Scope: 4 (Organization)

3. **Get Exception Record**
   - Action: "Get a record" (Dataverse)
   - Table: `fsi_SharingException`
   - Record ID: Trigger output

4. **Validate Business Justification**
   - Check length of `fsi_businessjustification` (minimum 50 characters)
   - If invalid, update status to "Rejected" and notify requester

5. **Route to Security Approver**
   - Get environment variable: `fsi_UASD_SecurityApproverEmail`
   - Action: "Start and wait for an approval"
   - Approval type: Approve/Reject
   - Title: `Exception Request: [Agent Name]`
   - Details: Include justification, requested date, data classification
   - **Timeout:** Configure a 14-day timeout on the approval action (ISO 8601: `P14D`). If the approver does not respond within 14 days, the action times out. Add a **Run after → Has timed out** branch to update `fsi_exceptionstatus` to Rejected with result `"Timed out: no approver response within 14 days"` and notify the requester. This prevents flows from silently failing at the 30-day Power Automate runtime limit.
   - **If security approver rejects:** Skip remaining approvals, go directly to step 7 rejection path
   - **If security approver approves:** Continue to step 6 for data-classification-based routing

6. **Check Data Classification** (only if security approver approved)
   - `fsi_dataclassification` value

   **If Confidential (100000002):**
   - Require data owner approval
   - Get environment variable: `fsi_UASD_DataOwnerApproverEmail`
   - Send approval request

   **If Restricted (100000003):**
   - Require data owner AND compliance approval
   - Get: `fsi_UASD_DataOwnerApproverEmail`
   - Get: `fsi_UASD_ComplianceApproverEmail`
   - Sequential approvals

   **If Public/Internal (100000000–100000001):**
   - Security approval only

7. **Process Approval Response**
   - If approved:
     - Update exception status to "Approved"
     - Calculate expiration: `fsi_requestedat + fsi_requestedduration` (in days). **Note:** If `fsi_requestedat` is null (e.g., records created via API), use `utcNow()` as fallback to prevent the `addDays` expression from failing.
     - Set `fsi_expiresat` field to calculated expiration date
     - Update related violation `fsi_violationstatus` to 100000002 (Exception Approved)
     - Notify requester (approval granted)

   > **Note — Duration enforcement:** The flow uses the user-submitted `fsi_requestedduration` as-is; it does not enforce classification-based maximum durations (Public/Internal: 90 days, Confidential: 60 days, Restricted: 30 days). Duration limits from the Approval Requirements table are **guidance for approvers**, not system-enforced caps. The `fsi_UASD_DefaultExceptionDays` environment variable is defined but not currently referenced by this flow or the Canvas App — it is reserved for future use as a pre-populated default or enforced cap. Approvers are responsible for rejecting requests that exceed recommended durations for the data classification.

   - If rejected:
     - Update exception status to "Rejected"
     - Notify requester with reason
     - Related violation remains "Open"

8. **Send Notifications**
   - Email to requester: Approval/rejection result
   - Teams message to compliance channel: Approval summary

**Trigger Configuration:**
```
Entity: fsi_SharingException
Trigger filters: fsi_exceptionstatus eq 100000000 (Pending only)
```
> **Note:** Since the trigger is Create-only and new records default to Pending (100000000), this filter is functionally equivalent to no filter but is included for consistency with SOLUTION-DOCUMENTATION.md and for clarity of intent.

---

## Flow 4: UASD-Exception-Expiration-Monitor

**Type:** Scheduled Cloud Flow
**Trigger:** Recurrence (Daily at 07:00 UTC)
**Purpose:** Proactively detect expired and expiring-soon exceptions, update statuses, and send Teams warning alerts

> **Note:** This flow does **not** check `fsi_UASD_RemediationDryRun`. Expiration status updates are metadata transitions (Approved → Expired), not remediation actions that modify agent sharing configurations. The flow always executes in full.

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Scheduled Cloud Flow
   - Flow name: `UASD-Exception-Expiration-Monitor`
   - Recurrence: Daily at 07:00 UTC (runs after Detector scan at 06:00 to avoid overlap)

2. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `warningDays`: Environment variable `fsi_UASD_ExpirationWarningDays` (default: 7)
   - `warningThreshold`: Expression `addDays(utcNow(), variables('warningDays'))`
   - `expiredCount`: Integer, initial value `0`
   - `warningCount`: Integer, initial value `0`
   - `teamsGroupId`: Environment variable `fsi_UASD_TeamsGroupId`
   - `teamsChannelId`: Environment variable `fsi_UASD_TeamsChannelId`

3. **Scope: Main Logic** (try block — see [Error Handling](#scope-based-trycatch-pattern))

4. **Query Expired Exceptions**
   - Action: "List records" (Dataverse)
   - Table: `fsi_SharingException`
   - Filter: `fsi_exceptionstatus eq 100000001 and fsi_expiresat lt @{variables('timestamp')}`
   - This returns all Approved exceptions whose expiration date has passed

5. **For Each Expired Exception → Update to Expired Status**
   - Loop through results from Step 4
   - Action: "Update a record" (Dataverse)
   - Table: `fsi_SharingException`
   - Record ID: Current item `fsi_sharingexceptionid`
   - Fields:
     - `fsi_exceptionstatus`: `100000003` (Expired)
   - Increment `expiredCount` variable

6. **Query Expiring-Soon Exceptions**
   - Action: "List records" (Dataverse)
   - Table: `fsi_SharingException`
   - Filter: `fsi_exceptionstatus eq 100000001 and fsi_expiresat gt @{variables('timestamp')} and fsi_expiresat lt @{variables('warningThreshold')}`
   - This returns Approved exceptions expiring within the warning window (default: 7 days) that have not yet expired

7. **For Each Expiring-Soon Exception → Send Warning**
   - Loop through results from Step 6
   - Increment `warningCount` variable
   - Action: "Post an Adaptive Card to a Teams Channel" (Teams)
   - Channel: Use `teamsGroupId` and `teamsChannelId`
   - Card body (inline JSON):

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.5",
  "body": [
    {
      "type": "ColumnSet",
      "columns": [
        {
          "type": "Column",
          "width": "auto",
          "items": [
            {
              "type": "TextBlock",
              "text": "⚠️",
              "size": "Large"
            }
          ]
        },
        {
          "type": "Column",
          "width": "stretch",
          "items": [
            {
              "type": "TextBlock",
              "text": "Exception Expiring Soon",
              "weight": "Bolder",
              "size": "Medium",
              "color": "Warning"
            }
          ]
        }
      ]
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Agent", "value": "@{items('Apply_to_each')?['fsi_agentname']}" },
        { "title": "Exception", "value": "@{items('Apply_to_each')?['fsi_name']}" },
        { "title": "Expires", "value": "@{formatDateTime(items('Apply_to_each')?['fsi_expiresat'], 'yyyy-MM-dd HH:mm UTC')}" },
        { "title": "Days Remaining", "value": "@{div(sub(ticks(items('Apply_to_each')?['fsi_expiresat']), ticks(utcNow())), 864000000000)}" },
        { "title": "Requested By", "value": "@{items('Apply_to_each')?['fsi_requestedby']}" },
        { "title": "Business Justification", "value": "@{items('Apply_to_each')?['fsi_businessjustification']}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "This exception will expire soon. The requester should submit a renewal via the Exception Manager app if continued access is needed. After expiration, the next Detector scan will create a new violation.",
      "wrap": true,
      "size": "Small"
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "Open Exception Manager",
      "url": "https://apps.powerapps.com/"
    }
  ]
}
```

8. **Send Summary Notification** (if any expirations or warnings found)
   - **Condition:** `or(greater(variables('expiredCount'), 0), greater(variables('warningCount'), 0))`
   - Action: "Post message in chat or channel" (Teams)
   - Channel: Use `teamsGroupId` and `teamsChannelId`
   - Message: `"UASD Exception Expiration Monitor: @{variables('expiredCount')} exception(s) expired, @{variables('warningCount')} exception(s) expiring within @{variables('warningDays')} days."`

9. **Scope: Catch** (error handling — configure **Run after** Main Logic: Failed, Timed out, Cancelled)
   - Send Teams alert with failure context (flow name, error message, run ID)
   - See [Error Handling](#scope-based-trycatch-pattern) for the standard pattern

**Trigger Configuration:**
- Frequency: Day
- Interval: 1
- Time zone: UTC
- Start time: 07:00 (after Detector scan completes)

---

## Canvas App: UASD-Exception-Manager

**Type:** Canvas App  
**Purpose:** User interface for submitting and tracking sharing exceptions

### Build Steps

1. **Create New App**
   - Power Apps → Create → Canvas App
   - App name: `UASD-Exception-Manager`
   - Format: Tablet or Phone + Tablet

2. **Add Data Sources**
   - Dataverse table: `fsi_SharingException`
   - Dataverse table: `fsi_SharingViolation`
   - Dataverse table: `fsi_AgentSharingSetting`
   - Dataverse table: `fsi_ApprovedSecurityGroup`

3. **Home Screen**
   - Title: "UASD Exception Manager"
   - Buttons:
     - "Submit New Exception"
     - "My Requests"
     - "Track Exceptions"
   - Status dashboard showing:
     - Total submitted
     - Pending approvals
     - Approved exceptions
     - Rejected exceptions

4. **Submit Exception Screen**
   - Form fields:
     - Agent (dropdown from `fsi_AgentSharingSetting` table)
     - Agent name (read-only)
     - Environment (read-only)
     - Violation type (read-only)
     - Data classification (dropdown: Public/Internal/Confidential/Restricted)
     - Business justification (text area, min 50 chars)
     - Requested duration (number, days; stored in fsi_RequestedDuration)
     - Submit button

   - Validation:
     - All required fields filled
     - Justification ≥ 50 characters
     - Duration > 0 and ≤ 36500 days (100 years)

   - On submit:
     - Create record in `fsi_SharingException` table
     - Set `fsi_requestedby` to current user
     - Set `fsi_requestedat` to now
     - Set `fsi_requestedduration` to user input
     - Set `fsi_exceptionstatus` to 100000000 (Pending)
     - Set `fsi_name` to `Concatenate("EXC-", Left(agentName, 60), "-", Text(Now(), "yyyyMMdd"))` — this provides a human-readable primary name (truncated to ≤100 chars) so exception records are identifiable in Dataverse views and audit queries
     - Show confirmation message
     - Navigate to tracking screen

5. **My Requests Screen**
   - Gallery showing user's exception requests
   - Columns: Agent, Status, Submitted Date, Expires
   - Filter: `fsi_requestedby = User().Email`
   - Sorting: By date descending
   - Detail view on tap

6. **Track Exceptions Screen**
   - Search by agent name
   - Filter options:
     - Status (Pending/Approved/Rejected/Expired)
     - Data classification
     - Approver assigned
   - Gallery with:
     - Agent name
     - Status badge (color-coded)
     - Submitted date
     - Expiration date
     - Approval chain display

7. **Settings Screen**
   - Display environment URL
   - Display current user email
   - Help documentation link
   - Feedback button

8. **Publish and Share**
   - Publish app
   - Share with:
     - Security groups authorized to submit exceptions
     - Compliance team (for auditing)
   - Assign security role with:
     - Read/Write on `fsi_SharingException`
     - Read on `fsi_SharingViolation`
     - Read on `fsi_AgentSharingSetting`
     - Read on `fsi_ApprovedSecurityGroup`

---

## Error Handling

All four flows make API calls (Power Platform, Dataverse, Teams) that can fail transiently. Apply these patterns to each flow:

### Scope-Based Try/Catch Pattern

Wrap the main logic of each flow in a **Scope** action (acts as a "try" block), then add parallel branches for error handling:

1. **Scope: Main Logic** — Contains all flow steps
2. **Scope: Catch** — Configure **Run after** to execute only when Main Logic has **Failed**, **Timed out**, or been **Cancelled**
   - Log error details to `fsi_remediationresult` or a dedicated error log
   - Send Teams alert with failure context (flow name, error message, run ID)
   - Set violation status appropriately (leave as Open so retries can pick it up)

### Run-After Configuration

For critical actions (API calls, Dataverse writes, Teams posts), configure **Run after** settings:

- **Is successful** → Continue normal flow
- **Has failed** → Branch to error handling (log error, send alert, terminate gracefully)
- **Has timed out** → Treat as transient failure, log and alert

### Retry Policies

For HTTP actions (Power Platform API calls in Flow 1 Step 5, Flow 2 Step 7):

- **Policy:** Exponential interval
- **Count:** 3 retries
- **Interval:** PT10S (10 seconds initial)
- **Maximum interval:** PT1M (1 minute)

For Dataverse connector actions, the connector applies default retry logic automatically. For Teams posting, configure a fixed retry of 2 attempts with PT5S interval.

---

## Connection References

Before deploying flows, create connection references in Power Automate:

| Connection Reference | API | Type |
|----------------------|-----|------|
| `fsi_cr_dataverse_sharingdetector` | Dataverse | Service Principal or User |
| `fsi_cr_teams_sharingdetector` | Microsoft Teams | Current User |
| `fsi_cr_approvals_sharingdetector` | Approvals | Current User |
| `fsi_cr_powerplatformadmin_sharingdetector` | Power Platform for Admins | Current User |

**Steps to Create Connection Reference:**
1. Power Automate → Solutions → UASD
2. New → Connection Reference
3. Name: `fsi_cr_dataverse_sharingdetector`
4. Connector: Dataverse
5. Create connection → Select authentication
6. Save

Repeat for Teams, Approvals, and Power Platform for Admins connectors.

---

## Flow Binding

After creating connection references:

1. Open each flow in edit mode
2. Navigate to **Data** → **Connection References**
3. For each connection reference in the flow:
   - Select the matching connection from the dropdown
   - Verify authentication method
4. Save and publish flow

---

## Deployment Validation

After building all flows and the Canvas app:

1. **Detector Flow Test**
   - Run manually → Should succeed
   - Check Dataverse table for populated agent settings

2. **Violation Creation Test**
   - Create test agent with org-wide sharing
   - Run Detector flow
   - Verify violation record created

3. **Remediation Test**
   - Check Remediation flow triggered on violation creation
   - Verify violation status updated

4. **Exception Request Test**
   - Open Exception Manager app
   - Submit exception with valid business justification
   - Verify approval request sent
   - Approve → Verify status updated

5. **End-to-End Flow**
   - Create violation → Remediation applied → Exception submitted → Approved → Violation marked as "Exception Approved"

---

## Troubleshooting

**Issue: Flow fails with "Invalid URI" error**
- **Cause:** Environment URL or API endpoint malformed
- **Resolution:** Verify `fsi_UASD_DataverseUrl` environment variable format (should be `https://org.crm.dynamics.com/`)

**Issue: Trigger not firing when violation created**
- **Cause:** Trigger filter may be excluding some records
- **Resolution:** Remove or adjust trigger filter, test with manual run

**Issue: Teams card not rendering**
- **Cause:** JSON schema mismatch or invalid channel/group ID
- **Resolution:** Validate `fsi_UASD_TeamsGroupId` and `fsi_UASD_TeamsChannelId` formats

**Issue: Dataverse connector "Access denied"**
- **Cause:** Connection user lacks required permissions
- **Resolution:** Verify user has Dataverse System Administrator or equivalent security role

---

## Next Steps

After completing flow deployment:
1. Configure environment variables (see main deployment guide)
2. Populate approved security groups registry
3. Enable flows in Power Automate
4. Monitor Detector flow runs for scan results
5. Train users on Exception Manager app

For comprehensive operational guidance, see the main SOLUTION-DOCUMENTATION.md.
