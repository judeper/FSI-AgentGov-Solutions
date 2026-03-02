# Flow Configuration Guide

## Overview

This guide provides step-by-step instructions for manually building the Unrestricted Agent Sharing Detector (UASD) Power Automate flows and Canvas app in Power Automate designer.

**Flows to Build:**
1. UASD-Detector-Scan-Agents (Scheduled Cloud Flow)
2. UASD-Remediation-Apply-Sharing-Policy (Automated Cloud Flow)
3. UASD-Exception-Approval-Workflow (Automated Cloud Flow)
4. UASD-Exception-Manager (Canvas App)

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

7. **Create Violation Records**
   - Action: "Create a new record" (Dataverse)
   - Table: `fsi_SharingViolation`
   - Fields:
     - `fsi_agentid`: Agent GUID
     - `fsi_agentname`: Agent display name
     - `fsi_environmentid`: Environment GUID
     - `fsi_violationtype`: Violation type code (100000000–100000004)
     - `fsi_violationstatus`: Open (100000000) — required field, no default
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
   - Action: "Get a record" (Dataverse)
   - Table: `fsi_AgentSharingSetting`
   - Filter: `fsi_agentid eq <violation's fsi_agentid>`
   - **Condition:** If `fsi_breakglassexclude = true`:
     - Update violation record `fsi_remediationresult` to `"Skipped: break-glass exclusion active"`
     - Send Teams notification indicating manual review required
     - Terminate flow (do not proceed to remediation)

4b. **Check for Active Exception**
   - Action: "List records" (Dataverse)
   - Table: `fsi_SharingException`
   - Filter: `fsi_agentid eq <violation's fsi_agentid> and fsi_exceptionstatus eq 100000001 and fsi_expiresat gt utcNow()`
   - **Condition:** If an active approved exception exists:
     - Update violation `fsi_violationstatus` to 100000002 (Exception Approved)
     - Update `fsi_remediationresult` to `"Skipped: active exception approved until <fsi_expiresat>"`
     - Terminate flow (do not proceed to remediation)

5. **Get Approved Security Groups for Zone**
   - Action: "List records" (Dataverse)
   - Table: `fsi_ApprovedSecurityGroup`
   - Filter: `fsi_zoneclassification eq <environment-zone> and fsi_isactive eq true`

6. **Remediate by Violation Type**
   - Use Switch statement on `fsi_violationtype`:

   **Case 100000000: ORG_WIDE_SHARING**
   - Remove organization-wide sharing
   - Add all approved security groups for zone

   **Case 100000001: PUBLIC_INTERNET_LINK**
   - **Condition:** If `equals(variables('autoRemediatePublicLink'), 'false')`, skip remediation actions — update `fsi_remediationresult` to `"Skipped: autoRemediatePublicLink is disabled"` and go to step 8
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
     - Do **not** set `fsi_violationstatus` to Remediated or `fsi_remediatedat`
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
Trigger filters:
  - fsi_violationstatus eq 100000000
  - fsi_remediatedat eq null
```

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
     - Duration > 0 and ≤ 365 days (1 year). Longer exceptions require renewal via a new request.

   - On submit:
     - Create record in `fsi_SharingException` table
     - Set `fsi_requestedby` to current user
     - Set `fsi_requestedat` to now
     - Set `fsi_requestedduration` to user input
     - Show confirmation message
     - Navigate to tracking screen

5. **My Requests Screen**
   - Gallery showing user's exception requests
   - Columns: Agent, Status, Submitted Date, Expires
   - Filter: `fsi_requestedby = CurrentUser.Email`
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

All three flows make API calls (Power Platform, Dataverse, Teams) that can fail transiently. Apply these patterns to each flow:

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
