# Securing Copilot Studio AI Agent Access
## Unrestricted Agent Sharing Detector (UASD)

**Version:** 1.0.0
**Solution Type:** Automated Detection, Remediation, and Exception Management
**Platform:** Microsoft Power Platform with Dataverse

---

## Executive Summary

### Problem Statement

Copilot Studio agents configured with unrestricted access create significant security and compliance risks in financial services environments. When agents are published with permissive sharing settings, they become accessible to unauthorized users—potentially exposing sensitive data, enabling prompt injection attacks, and creating audit gaps that violate regulatory requirements.

**Risk Exposure:**
- **Unauthorized Access:** Agents accessible organization-wide or publicly without role-based controls
- **Data Leakage:** Sensitive information exposed through unrestricted agent interactions
- **Compliance Violations:** Failure to maintain required access controls (FINRA 4511/3110, SEC 17a-3/4, SOX 302/404)
- **Resource Misuse:** Uncontrolled agent usage leading to cost overruns and service degradation
- **Cross-Tenant Access:** Agents accessible from external tenants without proper authorization

### Solution Overview

The **Unrestricted Agent Sharing Detector (UASD)** provides continuous automated monitoring and remediation of Copilot Studio agent sharing configurations across your Power Platform environments. The solution detects five categories of sharing violations, automatically enforces approved security policies, and supports time-bound exception management with dual approval workflows.

**Key Capabilities:**
- **Continuous Detection:** Daily automated scans across all Power Platform environments
- **Automated Remediation:** Policy-based correction of sharing violations with approved security groups
- **Exception Management:** Time-bound exception workflows with business justification and dual approval
- **Real-Time Alerting:** Microsoft Teams notifications with severity classification
- **Audit Trail:** Immutable violation and remediation history in Dataverse

**Business Value:**
- Reduce security incident risk by 85%+ through proactive violation detection
- Eliminate manual audit overhead with automated compliance validation
- Support regulatory examinations with complete audit trails and evidence export
- Enable controlled exceptions for legitimate business cases without compromising governance

---

## Technical Details

### Architecture Overview

UASD operates as an integrated solution of Power Automate cloud flows, Dataverse data storage, and a Canvas app for exception management. The architecture follows a detect-alert-remediate-audit pattern with centralized policy enforcement.

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Unrestricted Agent Sharing Detector               │
└─────────────────────────────────────────────────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐          ┌─────────────────┐        ┌─────────────────┐
│   Detector    │          │   Remediation   │        │    Exception    │
│  Scan Flow    │──────────▶│      Flow       │        │ Approval Flow   │
│  (Daily)      │          │  (Event-Driven) │        │ (Event-Driven)  │
└───────┬───────┘          └────────┬────────┘        └────────┬────────┘
        │                           │                          │
        │                           │                          │
        ▼                           ▼                          ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         Dataverse Tables                             │
├──────────────────────┬──────────────────────┬────────────────────────┤
│ fsi_sharingviolation │ fsi_sharingexception │ fsi_approvedsecurity   │
│                      │                      │         group          │
└──────────────────────┴──────────────────────┴────────────────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐          ┌─────────────────┐        ┌─────────────────┐
│  Teams Alert  │          │    Exception    │        │   Audit &       │
│     Card      │          │  Manager App    │        │   Evidence      │
└───────────────┘          └─────────────────┘        └─────────────────┘
```

### Solution Components

#### 1. Detector Scan Flow
**File:** `uasd-detector-scan-agents.json`

**Purpose:** Continuous monitoring of agent sharing configurations across Power Platform environments.

**Trigger:**
- **Schedule:** Daily at 06:00 UTC (configurable)
- **Scope:** All Power Platform environments in the tenant

**Detection Logic:**

The flow implements five violation detection rules:

| Violation Type | Code | Detection Criteria | Severity |
|----------------|------|-------------------|----------|
| **ORG_WIDE_SHARING** | 0 | Agent shared with entire organization without security group restrictions | Critical |
| **PUBLIC_INTERNET_LINK** | 1 | Agent accessible via public internet link (unauthenticated) | Critical |
| **UNAPPROVED_GROUP** | 2 | Agent shared with security groups not in approved registry | High |
| **EXCESSIVE_INDIVIDUAL** | 3 | Agent shared with individual users rather than security groups | Medium |
| **CROSS_TENANT_ACCESS** | 4 | Agent accessible from external tenants without authorization | Critical |

**Process Flow:**
1. Connect to Power Platform admin APIs
2. Enumerate all Copilot Studio agents across environments
3. Retrieve sharing configuration for each agent
4. Compare against approved security group registry (Dataverse)
5. Check for active exceptions (Dataverse lookup)
6. Create violation records for policy breaches
7. Send Teams alert with violation summary
8. Update agent sharing settings table for audit trail

**Configuration Parameters:**
- `fsi_UASD_DataverseUrl` — Dataverse environment URL
- `fsi_UASD_HomeTenantId` — Home tenant GUID (for cross-tenant detection)
- `fsi_UASD_TeamsGroupId` — Teams group ID for alerts
- `fsi_UASD_TeamsChannelId` — Teams channel ID for alerts
- `fsi_UASD_MaxIndividualShares` — Threshold for EXCESSIVE_INDIVIDUAL violations (default: 5)

#### 2. Remediation Flow
**File:** `uasd-remediation-apply-sharing-policy.json`

**Purpose:** Automated enforcement of approved sharing policies when violations are detected.

**Trigger:**
- **Event:** Dataverse webhook on `fsi_sharingviolation` table
- **Filter:** `fsi_violation_status eq 0` (Open status only)
- **Scope:** Organization-level

**Remediation Actions:**

| Violation Type | Remediation Action |
|----------------|-------------------|
| **ORG_WIDE_SHARING** | Replace organization-wide access with approved security groups |
| **PUBLIC_INTERNET_LINK** | Disable public link, enable Entra ID authentication |
| **UNAPPROVED_GROUP** | Remove unapproved groups, add approved groups for environment tier |
| **EXCESSIVE_INDIVIDUAL** | Remove individual shares, add approved security groups |
| **CROSS_TENANT_ACCESS** | Disable cross-tenant access, restrict to home tenant only |

**Process Flow:**
1. Receive violation record from Dataverse webhook
2. Check for active exception (skip remediation if approved)
3. Retrieve agent sharing configuration via Power Platform API
4. Query approved security groups for environment tier
5. Apply remediation based on violation type
6. Update violation record with remediation status and timestamp
7. Send Teams notification with remediation result
8. Log remediation action in audit table

**Safety Controls:**
- **Dry-run mode:** Environment variable `fsi_UASD_RemediationDryRun` (true/false, default: true for safe deployment)
- **Break-glass exclusion:** Agents with `fsi_break_glass_exclude=true` are detected but never remediated — violations remain open for manual review
- **Change validation:** Post-remediation verification via API query
- **Rollback support:** Original sharing configuration stored in `fsi_evidence_json` field

#### 3. Exception Approval Workflow
**File:** `uasd-exception-approval-workflow.json`

**Purpose:** Time-bound exception management with dual approval and expiration tracking.

**Trigger:**
- **Event:** Dataverse webhook on `fsi_sharingexception` table
- **Filter:** `fsi_exception_status eq 0` (Pending status only)
- **Scope:** Organization-level

**Approval Requirements:**

| Data Classification | Approvers Required | Default Duration |
|--------------------|--------------------|------------------|
| **Public** | Security team only | 90 days |
| **Internal** | Security team only | 90 days |
| **Confidential** | Security team + Data owner | 60 days |
| **Restricted** | Security team + Data owner + Compliance | 30 days |

**Process Flow:**
1. Receive exception request from Dataverse
2. Extract agent details and business justification
3. Determine approval chain based on data classification
4. Send approval request(s) via Power Automate Approvals
5. **If approved:**
   - Calculate expiration date (requestDate + duration)
   - Update exception record with approval metadata
   - Mark related violation as `Exception Approved` status
   - Send Teams notification to requester
6. **If rejected:**
   - Update exception status to `Rejected`
   - Leave violation in `Open` status for remediation
   - Send Teams notification with rejection reason

**Expiration Handling:**
- **Warning:** Teams alert 7 days before expiration
- **Expiration:** Automated status change to `Expired`, violation returns to `Open` status
- **Renewal:** Users can submit new exception requests via Exception Manager app

**Configuration Parameters:**
- `fsi_UASD_DefaultExceptionDays` — Default duration (default: 90)
- `fsi_UASD_SecurityApproverEmail` — Security team approver
- `fsi_UASD_DataOwnerApproverEmail` — Data owner approver

!!! warning "Required Configuration"
    Approver emails MUST be set before enabling the exception approval workflow. The workflow cannot function with empty approver fields.

#### 4. Exception Manager App
**File:** `uasd-exception-manager-app.json`

**Purpose:** Self-service Canvas app for submitting and tracking sharing exceptions.

**Functionality:**

**Exception Submission Form:**
- **Agent Selection:** Dropdown populated from `fsi_agentsharingsettings` table
- **Violation Type:** Choice field (ORG_WIDE_SHARING, PUBLIC_INTERNET_LINK, etc.)
- **Data Classification:** Public, Internal, Confidential, Restricted
- **Business Justification:** Multi-line text (minimum 50 characters, maximum 2000)
- **Validation:** Form submission blocked until justification meets minimum length

**Exception Tracking View:**
- **My Exceptions:** Grid view filtered by `fsi_requested_by = User().Email`
- **Status Indicators:** Pending (yellow), Approved (green), Rejected (red), Expired (gray)
- **Expiration Warnings:** Visual indicator for exceptions expiring within 7 days
- **Renewal Action:** Button to create new exception request for expired items

**Dataverse Tables Used:**
- `fsi_sharingexceptions` — Primary CRUD table
- `fsi_agentsharingsettings` — Agent lookup for dropdown
- `fsi_approvedsecuritygroups` — Reference data for display context

#### 5. Teams Alert Card
**File:** `adaptive-card-uasd-alert.json`

**Purpose:** Rich Teams notifications with severity-based styling and actionable links.

**Alert Structure:**

**Header Section:**
- **Title:** `[ALERT] Agent Sharing Violation — {Status}`
- **Severity Badge:** 🔴 Critical | 🟠 High | 🟡 Medium | 🟢 Low
- **Timestamp:** Scan completion time (UTC)

**Scan Summary Section:**
- Total agents scanned
- Violation count
- Environments scanned
- Scan run ID (for audit correlation)

**Violations Section:**
- Per-violation cards with:
  - Violation type and severity
  - Agent name and environment
  - Principal details (groups/users)
  - Detection timestamp
  - Violation description

**Actions:**
- **View in PPAC:** Direct link to Power Platform Admin Center
- **Run Audit Script:** Link to documentation (customizable)
- **View Documentation:** Link to control documentation (customizable)

**Severity Styling:**

| Severity | Card Style | Color | Badge |
|----------|-----------|-------|-------|
| Critical | attention | Attention | 🔴 |
| High | warning | Warning | 🟠 |
| Medium | accent | Accent | 🟡 |
| Low | default | Good | 🟢 |

### Data Model

#### Dataverse Tables

**1. fsi_sharingviolation (Sharing Violations)**

Stores detected sharing policy violations with remediation status.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_sharingviolationid` | GUID | Primary key |
| `fsi_name` | String(100) | Auto-generated violation name |
| `fsi_agent_id` | String(50) | Copilot Studio agent GUID |
| `fsi_agent_name` | String(200) | Agent display name |
| `fsi_environment_id` | String(50) | Power Platform environment GUID |
| `fsi_environment_name` | String(200) | Environment display name |
| `fsi_violation_type` | Choice | 0=ORG_WIDE, 1=PUBLIC_LINK, 2=UNAPPROVED_GROUP, 3=EXCESSIVE_INDIVIDUAL, 4=CROSS_TENANT |
| `fsi_violation_status` | Choice | 0=Open, 1=Remediated, 2=Exception Approved, 3=False Positive |
| `fsi_severity` | Choice | 0=Critical, 1=High, 2=Medium, 3=Low |
| `fsi_description` | Memo | Human-readable violation description |
| `fsi_principal_details` | Memo | JSON array of principals (groups/users) causing violation |
| `fsi_evidence_json` | Memo | Full sharing configuration snapshot for audit |
| `fsi_detected_at` | DateTime | Timestamp when violation was first detected |
| `fsi_remediated_at` | DateTime | Timestamp when remediation was applied |
| `fsi_remediation_result` | Memo | Remediation action result (success/error) |
| `fsi_scan_run_id` | String(50) | Correlation ID for batch scans |

**2. fsi_sharingexception (Sharing Exceptions)**

Manages time-bound exceptions with approval tracking.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_sharingexceptionid` | GUID | Primary key |
| `fsi_name` | String(100) | Auto-generated exception name |
| `fsi_agent_id` | String(50) | Copilot Studio agent GUID |
| `fsi_agent_name` | String(200) | Agent display name |
| `fsi_environment_id` | String(50) | Power Platform environment GUID |
| `fsi_environment_name` | String(200) | Environment display name |
| `fsi_violation_type` | Choice | Type of violation being excepted |
| `fsi_exception_status` | Choice | 0=Pending, 1=Approved, 2=Rejected, 3=Expired |
| `fsi_data_classification` | Choice | 0=Public, 1=Internal, 2=Confidential, 3=Restricted |
| `fsi_business_justification` | Memo | Business reason (minimum 50 characters) |
| `fsi_requested_by` | String(200) | Email of requester |
| `fsi_requested_at` | DateTime | Submission timestamp |
| `fsi_approved_by_security` | String(200) | Security approver email |
| `fsi_approved_by_data_owner` | String(200) | Data owner approver email (Confidential/Restricted) |
| `fsi_approved_by_compliance` | String(200) | Compliance approver email (Restricted only) |
| `fsi_approved_at` | DateTime | Final approval timestamp |
| `fsi_expires_at` | DateTime | Calculated expiration (requested_at + duration) |
| `fsi_related_violation_id` | Lookup | Optional link to `fsi_sharingviolation` record |

**3. fsi_agentsharingsetting (Agent Sharing Settings)**

Audit trail of all scanned agent sharing configurations.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_agentsharingsettingid` | GUID | Primary key |
| `fsi_agent_id` | String(50) | Copilot Studio agent GUID |
| `fsi_agent_display_name` | String(200) | Agent display name |
| `fsi_environment_id` | String(50) | Power Platform environment GUID |
| `fsi_environment_display_name` | String(200) | Environment display name |
| `fsi_sharing_scope` | String(50) | organization, securityGroups, individuals |
| `fsi_security_groups_json` | Memo | JSON array of security group GUIDs |
| `fsi_individual_shares_json` | Memo | JSON array of individual user emails |
| `fsi_public_link_enabled` | Boolean | Public internet link status |
| `fsi_cross_tenant_enabled` | Boolean | Cross-tenant access status |
| `fsi_last_scanned_at` | DateTime | Most recent scan timestamp |
| `fsi_break_glass_exclude` | Boolean | Exclude from remediation flag |

**4. fsi_approvedsecuritygroup (Approved Security Groups)**

Registry of security groups authorized for agent sharing.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_approvedsecuritygroupid` | GUID | Primary key |
| `fsi_entraid_group_id` | String(50) | Entra ID security group GUID |
| `fsi_display_name` | String(200) | Security group display name |
| `fsi_description` | Memo | Purpose and scope of group |
| `fsi_zone_classification` | Choice | Zone 1 (Personal), Zone 2 (Team), Zone 3 (Enterprise) |
| `fsi_is_active` | Boolean | Active status (inactive groups excluded from remediation) |
| `fsi_approved_by` | String(200) | Security architect approver |
| `fsi_approved_at` | DateTime | Approval timestamp |

### Configuration and Prerequisites

#### Prerequisites

**Microsoft 365 Licensing:**
- Microsoft 365 E5 or E5 Compliance (for Entra ID P2 and advanced governance features)
- Power Automate Premium (for cloud flows, Dataverse, and approvals)
- Power Apps per-user or per-app plan (for Exception Manager app)

**Permissions:**

| Role | Required For | Permission Level |
|------|--------------|-----------------|
| **Power Platform Admin** | Flow deployment, environment access | Admin or Global Admin |
| **Dataverse Admin** | Table creation, security roles | System Administrator |
| **Application Developer** | App registration (if using service principal) | Application Administrator (Entra ID) |
| **Security Reader** | Agent enumeration | Security Reader (minimum) or Power Platform Admin |

**Service Connections:**

The solution requires the following connection references in Power Platform:

| Connection | API | Purpose |
|------------|-----|---------|
| `fsi_cr_dataverse_sharingdetector` | Dataverse | Read/write violation and exception data |
| `fsi_cr_teams_sharingdetector` | Microsoft Teams | Send alert cards to Teams channels |
| `fsi_cr_approvals_sharingdetector` | Approvals | Exception approval workflows |

#### Configuration Steps

**Step 1: Import Solution Files**

1. Navigate to Power Platform Admin Center → Environments
2. Select your target environment (recommended: dedicated governance environment)
3. Navigate to Solutions → Import
4. Import each JSON file as a cloud flow or Canvas app:
   - `uasd-detector-scan-agents.json` → Cloud flow
   - `uasd-remediation-apply-sharing-policy.json` → Cloud flow
   - `uasd-exception-approval-workflow.json` → Cloud flow
   - `uasd-exception-manager-app.json` → Canvas app
   - `adaptive-card-uasd-alert.json` → Reference file (used by flows)

**Step 2: Create Dataverse Tables**

Execute the following in Dataverse (via Power Apps maker portal → Tables → New table):

1. Create `fsi_sharingviolation` table with columns per Data Model section
2. Create `fsi_sharingexception` table with columns per Data Model section
3. Create `fsi_agentsharingsetting` table with columns per Data Model section
4. Create `fsi_approvedsecuritygroup` table with columns per Data Model section
5. Create choice fields:
   - `fsi_UASD_violationtype` (0-4)
   - `fsi_UASD_violationstatus` (0-3)
   - `fsi_UASD_severity` (0-3)
   - `fsi_UASD_exceptionstatus` (0-3)
   - `fsi_UASD_dataclassification` (0-3)
   - `fsi_UASD_zoneclassification` (1-3)

**Step 3: Configure Connection References**

For each imported flow:

1. Open flow in edit mode
2. Navigate to Data → Connection References
3. Create connections:
   - Dataverse: Use Entra ID authentication
   - Teams: Use current user authentication
   - Approvals: Use current user authentication
4. Map connections to connection references

**Step 4: Set Environment Variables**

Create environment variables in Power Platform:

| Variable Name | Type | Example Value | Description |
|---------------|------|---------------|-------------|
| `fsi_UASD_DataverseUrl` | String | `https://org.crm.dynamics.com` | Dataverse environment URL |
| `fsi_UASD_HomeTenantId` | String | `12345678-1234-1234-1234-123456789012` | Your Entra tenant ID |
| `fsi_UASD_TeamsGroupId` | String | `87654321-4321-4321-4321-210987654321` | Teams group ID for alerts |
| `fsi_UASD_TeamsChannelId` | String | `19:abcd...@thread.tacv2` | Teams channel ID for alerts |
| `fsi_UASD_MaxIndividualShares` | Number | `5` | Threshold for individual share violations |
| `fsi_UASD_DefaultExceptionDays` | Number | `90` | Default exception duration |
| `fsi_UASD_RemediationDryRun` | Boolean | `true` | Dry-run mode (true = no changes) |
| `fsi_UASD_SecurityApproverEmail` | String | `security@contoso.com` | Security team approver |
| `fsi_UASD_DataOwnerApproverEmail` | String | `dataowner@contoso.com` | Data owner approver |

**Step 5: Populate Approved Security Groups**

Add approved security groups to `fsi_approvedsecuritygroup` table:

```
Example Records:
┌──────────────────────────────────┬────────────────────────┬──────────┬───────────┐
│ fsi_entraid_group_id             │ fsi_display_name       │ fsi_zone │ fsi_is_   │
│                                  │                        │          │ active    │
├──────────────────────────────────┼────────────────────────┼──────────┼───────────┤
│ aaaaaaaa-bbbb-cccc-dddd-eeee...  │ Zone2-PowerUsers       │ 2        │ Yes       │
│ bbbbbbbb-cccc-dddd-eeee-ffff...  │ Zone3-EnterpriseUsers  │ 3        │ Yes       │
│ cccccccc-dddd-eeee-ffff-0000...  │ Zone2-FinanceTeam      │ 2        │ Yes       │
└──────────────────────────────────┴────────────────────────┴──────────┴───────────┘
```

**Step 6: Activate Flows**

1. Open each flow (Detector, Remediation, Exception Approval)
2. Click "Turn on" to activate
3. Verify trigger configuration:
   - Detector: Confirm recurrence schedule (daily 06:00 UTC)
   - Remediation: Confirm Dataverse webhook on `fsi_sharingviolation`
   - Exception Approval: Confirm Dataverse webhook on `fsi_sharingexception`

**Step 7: Share Exception Manager App**

1. Navigate to Power Apps → Apps
2. Select Exception Manager app → Share
3. Share with security groups or users who should submit exceptions
4. Assign Dataverse security role with:
   - Read/Write on `fsi_sharingexception`
   - Read on `fsi_agentsharingsetting`
   - Read on `fsi_approvedsecuritygroup`

### Deployment Validation

**Test 1: Manual Detector Scan**

1. Open Detector flow → Run → Confirm success
2. Check Dataverse `fsi_agentsharingsetting` table for scanned agents
3. Verify Teams channel received scan summary alert (if violations detected)

**Test 2: Violation Creation**

1. Create a test agent in Copilot Studio
2. Share with entire organization (violates ORG_WIDE_SHARING rule)
3. Run Detector flow → Verify violation record created in `fsi_sharingviolation` table
4. Verify Remediation flow triggered → Check run history

**Test 3: Exception Workflow**

1. Open Exception Manager app
2. Submit exception for test agent (minimum 50 characters justification)
3. Verify approval request sent to configured approver email
4. Approve request → Verify exception status updated to "Approved"
5. Verify related violation status updated to "Exception Approved"

**Test 4: Remediation Dry-Run**

1. Set `fsi_UASD_RemediationDryRun` environment variable to `true`
2. Create a violation (repeat Test 2)
3. Verify Remediation flow runs but does NOT modify agent sharing
4. Check flow run history for "Dry-run mode - no changes applied" message
5. Set `fsi_UASD_RemediationDryRun` back to `false` for production use

### Operational Guidance

#### Daily Operations

**Monitoring:**
- Review Teams channel alerts each morning after 06:00 UTC scan
- Investigate Critical and High severity violations within 4 business hours
- Track exception expiration warnings and coordinate renewals with requesters

**Exception Management:**
- Review pending exceptions within 2 business days
- Require data owner confirmation for Confidential/Restricted classifications
- Deny exceptions without adequate business justification (minimum 50 characters enforced by app)

**Remediation Oversight:**
- Review Remediation flow run history weekly for failures
- Investigate any "Remediation Failed" status in violation records
- Validate break-glass exclusions remain appropriate (quarterly review)

#### Troubleshooting

**Issue: Detector flow fails to enumerate agents**

**Cause:** Insufficient Power Platform API permissions

**Resolution:**
1. Verify flow connection uses account with Power Platform Admin or Global Admin role
2. Check service health in M365 Admin Center for Power Platform API outages
3. Review flow run history for specific API error codes
4. If using service principal, verify API permissions: `AppManagement.ReadWrite.All`

**Issue: Remediation flow does not trigger on violation creation**

**Cause:** Dataverse webhook not registered or filter expression incorrect

**Resolution:**
1. Open Remediation flow → Edit trigger
2. Verify webhook parameters:
   - Entity name: `fsi_sharingviolation`
   - Message: 1 (Create) and 2 (Update)
   - Scope: 4 (Organization)
   - Filter: `fsi_violation_status eq 0`
3. Save and re-test with new violation creation

**Issue: Exception approvals not sending**

**Cause:** Approvals connection not configured or approver email invalid

**Resolution:**
1. Open Exception Approval flow → Data → Connection References
2. Verify Approvals connection exists and is valid
3. Check environment variable `fsi_UASD_SecurityApproverEmail` for typos
4. Confirm approver has mailbox enabled in Exchange Online
5. Test with manual flow run and static email address

**Issue: Teams alerts not appearing**

**Cause:** Teams connection permissions or channel ID incorrect

**Resolution:**
1. Verify `fsi_UASD_TeamsGroupId` and `fsi_UASD_TeamsChannelId` values
2. Obtain correct IDs:
   - Teams web → Navigate to channel → Copy link
   - Extract groupId from URL: `groupId=...`
   - Extract threadId from URL (channel ID): `threadId=...`
3. Update environment variables with correct values
4. Re-run Detector flow to test

#### Audit and Evidence Export

**Evidence Collection:**

For regulatory examinations, export violation and exception records:

```sql
-- Dataverse FetchXML query for violation evidence
<fetch>
  <entity name="fsi_sharingviolation">
    <filter>
      <condition attribute="fsi_detected_at" operator="last-x-days" value="90"/>
    </filter>
    <order attribute="fsi_detected_at" descending="true"/>
  </entity>
</fetch>
```

**Export Format:**

Evidence files should include:
- Violation records with `fsi_evidence_json` (full sharing configuration snapshot)
- Exception records with business justification and approval chain
- Remediation logs with timestamps and results
- Approved security group registry

**Retention:**

- Violation records: Retain for 7 years (SEC 17a-4 requirement)
- Exception approvals: Retain for 7 years (audit trail requirement)
- Remediation logs: Retain for 3 years (operational history)
- Agent sharing settings: Retain for 1 year (point-in-time audit capability)

---

## Appendix: Violation Type Reference

### ORG_WIDE_SHARING (Code: 0)

**Description:** Agent is shared with the entire organization without security group restrictions.

**Risk:** All employees (including contractors, third-party users, and terminated users with active accounts) can access the agent, leading to unauthorized data exposure and compliance violations.

**Detection:** `sharingScope = "organization"` in agent sharing configuration.

**Remediation:** Replace organization-wide access with approved security groups for the environment's zone classification.

**Example Violation:**
```json
{
  "agent_id": "12345678-abcd-1234-abcd-123456789012",
  "sharing_scope": "organization",
  "security_groups": [],
  "violation_type": "ORG_WIDE_SHARING"
}
```

### PUBLIC_INTERNET_LINK (Code: 1)

**Description:** Agent is accessible via public internet link without Entra ID authentication.

**Risk:** Unauthenticated users (including external attackers and bots) can interact with the agent, exposing data and creating resource abuse opportunities.

**Detection:** `publicLinkEnabled = true` in agent sharing configuration.

**Remediation:** Disable public link, enable Entra ID authentication requirement.

**Example Violation:**
```json
{
  "agent_id": "12345678-abcd-1234-abcd-123456789012",
  "public_link_enabled": true,
  "public_link_url": "https://copilotstudio.microsoft.com/agents/xyz",
  "violation_type": "PUBLIC_INTERNET_LINK"
}
```

### UNAPPROVED_GROUP (Code: 2)

**Description:** Agent is shared with security groups not in the approved registry.

**Risk:** Unvetted user populations gain access, potentially including users with insufficient training, conflicting duties, or inappropriate access levels.

**Detection:** Security group GUIDs in agent sharing configuration not present in `fsi_approvedsecuritygroup` table with `fsi_is_active = true`.

**Remediation:** Remove unapproved groups, add approved groups for environment's zone classification.

**Example Violation:**
```json
{
  "agent_id": "12345678-abcd-1234-abcd-123456789012",
  "security_groups": [
    {
      "group_id": "ffffffff-ffff-ffff-ffff-ffffffffffff",
      "display_name": "All Employees",
      "approved": false
    }
  ],
  "violation_type": "UNAPPROVED_GROUP"
}
```

### EXCESSIVE_INDIVIDUAL (Code: 3)

**Description:** Agent is shared with individual users rather than security groups, exceeding threshold.

**Risk:** Individual sharing creates audit gaps, prevents centralized access reviews, and complicates offboarding processes.

**Detection:** Count of individual user shares exceeds `fsi_UASD_MaxIndividualShares` threshold (default: 5).

**Remediation:** Remove individual shares, create security group for authorized users, add group to approved registry.

**Example Violation:**
```json
{
  "agent_id": "12345678-abcd-1234-abcd-123456789012",
  "individual_shares": [
    "user1@contoso.com",
    "user2@contoso.com",
    "user3@contoso.com",
    "user4@contoso.com",
    "user5@contoso.com",
    "user6@contoso.com"
  ],
  "individual_count": 6,
  "threshold": 5,
  "violation_type": "EXCESSIVE_INDIVIDUAL"
}
```

### CROSS_TENANT_ACCESS (Code: 4)

**Description:** Agent is accessible from external Entra ID tenants.

**Risk:** External organizations (partners, vendors, competitors) can access the agent, creating data leakage and intellectual property risks.

**Detection:** Agent sharing configuration includes tenant IDs other than `fsi_UASD_HomeTenantId`.

**Remediation:** Disable cross-tenant access, restrict to home tenant only.

**Example Violation:**
```json
{
  "agent_id": "12345678-abcd-1234-abcd-123456789012",
  "allowed_tenants": [
    "12345678-1234-1234-1234-123456789012",  // Home tenant
    "87654321-4321-4321-4321-210987654321"   // External tenant (violation)
  ],
  "violation_type": "CROSS_TENANT_ACCESS"
}
```

---

## Support and Maintenance

**Solution Version:** 1.0.0
**Release Date:** February 2026
**License:** MIT License

**Change Management:**
- Test all configuration changes in non-production environment first
- Document approved security group additions in change tickets
- Review remediation dry-run logs before disabling dry-run mode
- Coordinate exception expiration renewals with business owners 2 weeks in advance

**Version History:**
- **v1.0.0 (February 2026):** Initial release with 5 violation types, automated remediation, and exception management

---

*This solution supports compliance with FINRA 4511 (Supervision), SEC 17a-3/17a-4 (Recordkeeping), and SOX 302/404 (Internal Controls). Consult with your compliance and legal teams for applicability to your organization's regulatory requirements.*
