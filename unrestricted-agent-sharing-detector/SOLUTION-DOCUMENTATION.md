# Securing Copilot Studio AI Agent Access
## Unrestricted Agent Sharing Detector (UASD)

**Version:** 1.0.2
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
- Supports reduction of security incident risk through proactive violation detection
- Helps reduce manual audit overhead with automated compliance validation
- Support regulatory examinations with complete audit trails and evidence export
- Enable controlled exceptions for legitimate business cases without compromising governance

---

## Technical Details

### Architecture Overview

UASD operates as an integrated solution of Power Automate cloud flows, Dataverse data storage, and a Canvas app for exception management. The architecture follows a detect-alert-remediate-audit pattern with centralized policy enforcement.

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                        Unrestricted Agent Sharing Detector                            │
└──────────────────────────────────────────────────────────────────────────────────────┘
                                           │
        ┌──────────────────┬───────────────┼───────────────┬──────────────────┐
        │                  │               │               │                  │
        ▼                  ▼               ▼               ▼                  ▼
┌───────────────┐ ┌─────────────────┐ ┌─────────────────┐ ┌──────────────────┐
│   Detector    │ │   Remediation   │ │    Exception    │ │   Expiration     │
│  Scan Flow    │─▶│      Flow       │ │ Approval Flow   │ │  Monitor Flow   │
│  (Daily)      │ │  (Event-Driven) │ │ (Event-Driven)  │ │  (Daily)         │
└───────┬───────┘ └────────┬────────┘ └────────┬────────┘ └────────┬─────────┘
        │                  │                   │                   │
        ▼                  ▼                   ▼                   ▼
┌──────────────────────────────────────────────────────────────────────────────────────┐
│                                  Dataverse Tables                                    │
├──────────────────────┬──────────────────────┬──────────────────────┬─────────────────┤
│ fsi_SharingViolation │ fsi_SharingException │ fsi_ApprovedSecurity │ fsi_AgentSharing│
│                      │                      │         Group        │     Setting     │
└──────────────────────┴──────────────────────┴──────────────────────┴─────────────────┘
                                           │
        ┌──────────────────────────────────┼──────────────────────────────────┐
        │                                  │                                  │
        ▼                                  ▼                                  ▼
┌───────────────┐                 ┌─────────────────┐                ┌─────────────────┐
│  Teams Alert  │                 │    Exception    │                │   Audit &       │
│     Card      │                 │  Manager App    │                │   Evidence      │
└───────────────┘                 └─────────────────┘                └─────────────────┘
```

### Solution Components

#### 1. Detector Scan Flow
**Build instructions:** [docs/flow-configuration.md](docs/flow-configuration.md#flow-1-uasd-detector-scan-agents)

**Purpose:** Continuous monitoring of agent sharing configurations across Power Platform environments.

**Trigger:**
- **Schedule:** Daily at 06:00 UTC (configurable)
- **Scope:** All Power Platform environments in the tenant

**Detection Logic:**

The flow implements five violation detection rules:

| Violation Type | Code | Detection Criteria | Severity |
|----------------|------|-------------------|----------|
| **ORG_WIDE_SHARING** | 100000000 | Agent shared with entire organization without security group restrictions | Critical |
| **PUBLIC_INTERNET_LINK** | 100000001 | Agent accessible via public internet link (unauthenticated) | Critical |
| **UNAPPROVED_GROUP** | 100000002 | Agent shared with security groups not in approved registry | High |
| **EXCESSIVE_INDIVIDUAL** | 100000003 | Agent shared with individual users rather than security groups | Medium |
| **CROSS_TENANT_ACCESS** | 100000004 | Agent accessible from external tenants without authorization | Critical |

**Process Flow:**
1. Connect to Power Platform admin APIs
2. Enumerate all Copilot Studio agents across environments
3. Retrieve sharing configuration for each agent
4. Compare against approved security group registry (Dataverse)
5. Create violation records for policy breaches (with deduplication)
6. Send Teams alert with violation summary
7. Update agent sharing settings table for audit trail

> **Note:** Exception checking is performed by the Remediation flow (Flow 2, Step 4b), not by the Detector flow. The Detector creates violation records unconditionally; the Remediation flow then checks for active exceptions before applying remediation.

**Configuration Parameters:**
- `fsi_UASD_DataverseUrl` — Dataverse environment URL
- `fsi_UASD_HomeTenantId` — Home tenant GUID (for cross-tenant detection)
- `fsi_UASD_TeamsGroupId` — Teams group ID for alerts
- `fsi_UASD_TeamsChannelId` — Teams channel ID for alerts
- `fsi_UASD_MaxIndividualShares` — Threshold for EXCESSIVE_INDIVIDUAL violations (default: 5)

#### 2. Remediation Flow
**Build instructions:** [docs/flow-configuration.md](docs/flow-configuration.md#flow-2-uasd-remediation-apply-sharing-policy)

**Purpose:** Automated enforcement of approved sharing policies when violations are detected.

**Trigger:**
- **Event:** Dataverse webhook on `fsi_SharingViolation` table
- **Filter:** `fsi_violationstatus eq 100000000 and fsi_remediatedat eq null` (Open, not yet remediated)
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
2. Check break-glass exclusion (skip remediation if `fsi_breakglassexclude=true`, set violation to Excluded status 100000004)
3. Check for active exception (skip remediation if approved)
4. Retrieve agent sharing configuration via Power Platform API
5. Query approved security groups for environment tier
6. Apply remediation based on violation type
7. Update violation record with remediation status and timestamp
8. Send Teams notification with remediation result
9. Log remediation action in audit table

**Safety Controls:**
- **Dry-run mode:** Environment variable `fsi_UASD_RemediationDryRun` (true/false, default: true for safe deployment)
- **Break-glass exclusion:** Agents with `fsi_breakglassexclude=true` are detected but never remediated — violations are set to Excluded status (100000004) for manual review
- **Change validation:** Post-remediation verification via API query
- **Rollback support:** Original sharing configuration stored in `fsi_evidencejson` field

#### 3. Exception Approval Workflow
**Build instructions:** [docs/flow-configuration.md](docs/flow-configuration.md#flow-3-uasd-exception-approval-workflow)

**Purpose:** Time-bound exception management with dual approval and expiration tracking.

**Trigger:**
- **Event:** Dataverse webhook on `fsi_SharingException` table
- **Filter:** `fsi_exceptionstatus eq 100000000` (Pending status only)
- **Scope:** Organization-level

**Approval Requirements:**

| Data Classification | Approvers Required | Default Duration |
|--------------------|--------------------|------------------|
| **Public** | Security team only | 90 days |
| **Internal** | Security team only | 90 days |
| **Confidential** | Security team + Data owner | 60 days |
| **Restricted** | Security team + Data owner + Compliance | 30 days |

> **Note:** These default durations are **guidance for approvers**, not system-enforced caps. Flow 3 calculates expiration using the user-submitted `fsi_requestedduration` without enforcing classification-based limits. Approvers are responsible for rejecting requests that exceed the recommended durations above.

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

### Expiration Handling

The fourth flow, **UASD-Exception-Expiration-Monitor**, runs daily and handles two expiration scenarios:

1. **Expired exceptions:** Queries `fsi_SharingException` for records where `fsi_exceptionstatus eq 100000001` (Approved) and `fsi_expiresat lt utcNow()`. Updates matched records to `fsi_exceptionstatus = 100000003` (Expired). On the next Detector scan, violations previously covered by these exceptions will no longer match an active exception (the `fsi_expiresat gt utcNow()` filter in Flow 2 Step 4b will exclude them), creating new violation records for remediation.
2. **Expiring-soon warnings:** Queries for Approved exceptions where `fsi_expiresat lt addDays(utcNow(), warningDays)` (default: 7 days, configurable via `fsi_UASD_ExpirationWarningDays`). Sends Teams adaptive card alerts prompting requesters to submit renewal requests via the Exception Manager app before expiration.

See `docs/flow-configuration.md` Flow 4 for step-by-step build instructions.

- **Renewal:** Users can submit new exception requests via Exception Manager app

**Configuration Parameters:**
- `fsi_UASD_DefaultExceptionDays` — Default duration (default: 90). **Not currently referenced** by any flow or Canvas App; reserved for future use as a pre-populated default or enforced duration cap.
- `fsi_UASD_SecurityApproverEmail` — Security team approver
- `fsi_UASD_DataOwnerApproverEmail` — Data owner approver
- `fsi_UASD_ComplianceApproverEmail` — Compliance approver (required for Restricted data)

!!! warning "Required Configuration"
    Approver emails MUST be set before enabling the exception approval workflow. The workflow cannot function with empty approver fields.

#### 4. Exception Manager App
**Build instructions:** [docs/flow-configuration.md](docs/flow-configuration.md#canvas-app-uasd-exception-manager)

**Purpose:** Self-service Canvas app for submitting and tracking sharing exceptions.

**Functionality:**

**Exception Submission Form:**
- **Agent Selection:** Dropdown populated from `fsi_AgentSharingSetting` table
- **Violation Type:** Choice field (ORG_WIDE_SHARING, PUBLIC_INTERNET_LINK, etc.)
- **Data Classification:** Public, Internal, Confidential, Restricted
- **Business Justification:** Multi-line text (minimum 50 characters, maximum 2000)
- **Validation:** Form submission blocked until justification meets minimum length

**Exception Tracking View:**
- **My Exceptions:** Grid view filtered by `fsi_requestedby = User().Email`
- **Status Indicators:** Pending (yellow), Approved (green), Rejected (red), Expired (gray)
- **Expiration Warnings:** Visual indicator for exceptions expiring within 7 days
- **Renewal Action:** Button to create new exception request for expired items

**Dataverse Tables Used:**
- `fsi_SharingException` — Primary CRUD table
- `fsi_SharingViolation` — Violation records display and tracking
- `fsi_AgentSharingSetting` — Agent lookup for dropdown
- `fsi_ApprovedSecurityGroup` — Reference data for display context

#### 5. Teams Alert Card
**Template:** Defined during manual flow build (see Flow 1, step 8 in `docs/flow-configuration.md` for configuration guidance)

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

For complete table definitions, column names (with Dataverse logical names), option sets, and relationships, see **[docs/dataverse-schema.md](docs/dataverse-schema.md)** — auto-generated from the schema script.

**Tables:** `fsi_SharingViolation`, `fsi_SharingException`, `fsi_AgentSharingSetting`, `fsi_ApprovedSecurityGroup`, `fsi_SharingPolicy`

!!! note "`fsi_SharingPolicy` — Reserved for Future Use"
    The `fsi_SharingPolicy` table is defined in the Dataverse schema and provisioned by the setup scripts, but is **not currently referenced by any flow, Canvas app, or governance script**. It is intended for future per-zone policy enforcement (e.g., zone-specific thresholds for `fsi_maxindividualshares`, `fsi_alloworgwidesharing`). Currently, the Remediation flow (Flow 2 Step 5) queries `fsi_ApprovedSecurityGroup` by zone but does not consult `fsi_SharingPolicy` for zone-specific rules. The table can be safely ignored until policy-driven remediation is implemented.

To regenerate the schema reference after any changes:
```bash
python scripts/create_uasd_dataverse_schema.py --output-docs
```

<!--
REMOVED: Hand-maintained column listings previously here (lines 273-372).
Now auto-generated in docs/dataverse-schema.md from the schema script.
-->

<!-- BEGIN REMOVED SECTION (preserved as comment for reference)
**1. fsi_SharingViolation (Sharing Violations)**

Stores detected sharing policy violations with remediation status.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_sharingviolationid` | GUID | Primary key |
| `fsi_name` | String(100) | Auto-generated violation name |
| `fsi_agentid` | String(50) | Copilot Studio agent GUID |
| `fsi_agentname` | String(200) | Agent display name |
| `fsi_environmentid` | String(50) | Power Platform environment GUID |
| `fsi_environmentname` | String(200) | Environment display name |
| `fsi_violationtype` | Choice | 100000000=ORG_WIDE, 100000001=PUBLIC_LINK, 100000002=UNAPPROVED_GROUP, 100000003=EXCESSIVE_INDIVIDUAL, 100000004=CROSS_TENANT |
| `fsi_violationstatus` | Choice | 100000000=Open, 100000001=Remediated, 100000002=Exception Approved, 100000003=False Positive, 100000004=Excluded, 100000005=Skipped, 100000006=Dry Run |
| `fsi_severity` | Choice | 100000000=Critical, 100000001=High, 100000002=Medium, 100000003=Low |
| `fsi_description` | Memo | Human-readable violation description |
| `fsi_principaldetails` | Memo | JSON array of principals (groups/users) causing violation |
| `fsi_evidencejson` | Memo | Full sharing configuration snapshot for audit |
| `fsi_detectedat` | DateTime | Timestamp when violation was first detected |
| `fsi_remediatedat` | DateTime | Timestamp when remediation was applied |
| `fsi_remediationresult` | Memo | Remediation action result (success/error) |
| `fsi_scanrunid` | String(50) | Correlation ID for batch scans |

**2. fsi_SharingException (Sharing Exceptions)**

Manages time-bound exceptions with approval tracking.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_sharingexceptionid` | GUID | Primary key |
| `fsi_name` | String(100) | Auto-generated exception name |
| `fsi_agentid` | String(50) | Copilot Studio agent GUID |
| `fsi_agentname` | String(200) | Agent display name |
| `fsi_environmentid` | String(50) | Power Platform environment GUID |
| `fsi_environmentname` | String(200) | Environment display name |
| `fsi_violationtype` | Choice | Type of violation being excepted |
| `fsi_exceptionstatus` | Choice | 100000000=Pending, 100000001=Approved, 100000002=Rejected, 100000003=Expired |
| `fsi_dataclassification` | Choice | 100000000=Public, 100000001=Internal, 100000002=Confidential, 100000003=Restricted |
| `fsi_businessjustification` | Memo | Business reason (minimum 50 characters) |
| `fsi_requestedby` | String(200) | Email of requester |
| `fsi_requestedat` | DateTime | Submission timestamp |
| `fsi_approvedbysecurity` | String(200) | Security approver email |
| `fsi_approvedbydataowner` | String(200) | Data owner approver email (Confidential/Restricted) |
| `fsi_approvedbycompliance` | String(200) | Compliance approver email (Restricted only) |
| `fsi_approvedat` | DateTime | Final approval timestamp |
| `fsi_expiresat` | DateTime | Calculated expiration (requested_at + duration) |
| `fsi_relatedviolationid` | Lookup | Optional link to `fsi_SharingViolation` record |

**3. fsi_AgentSharingSetting (Agent Sharing Settings)**

Audit trail of all scanned agent sharing configurations.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_agentsharingsettingid` | GUID | Primary key |
| `fsi_agentid` | String(50) | Copilot Studio agent GUID |
| `fsi_agentdisplayname` | String(200) | Agent display name |
| `fsi_environmentid` | String(50) | Power Platform environment GUID |
| `fsi_environmentdisplayname` | String(200) | Environment display name |
| `fsi_sharingscope` | String(50) | organization, securityGroups, individuals |
| `fsi_securitygroupsjson` | Memo | JSON array of security group GUIDs |
| `fsi_individualsharesjson` | Memo | JSON array of individual user emails |
| `fsi_publiclinkenabled` | Boolean | Public internet link status |
| `fsi_crosstenantenabled` | Boolean | Cross-tenant access status |
| `fsi_lastscannedat` | DateTime | Most recent scan timestamp |
| `fsi_breakglassexclude` | Boolean | Exclude from remediation flag |

**4. fsi_ApprovedSecurityGroup (Approved Security Groups)**

Registry of security groups authorized for agent sharing.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_approvedsecuritygroupid` | GUID | Primary key |
| `fsi_entraidgroupid` | String(50) | Entra ID security group GUID |
| `fsi_displayname` | String(200) | Security group display name |
| `fsi_description` | Memo | Purpose and scope of group |
| `fsi_zoneclassification` | Choice | Zone 1 (Personal), Zone 2 (Team), Zone 3 (Enterprise) |
| `fsi_isactive` | Boolean | Active status (inactive groups excluded from remediation) |
| `fsi_approvedby` | String(200) | Security architect approver |
| `fsi_approvedat` | DateTime | Approval timestamp |

**5. fsi_SharingPolicy (Sharing Policies)**

Per-zone sharing policy definitions including thresholds and enforcement settings.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_sharingpolicyid` | GUID | Primary key |
| `fsi_name` | String(100) | Policy display name |
| `fsi_zoneclassification` | Choice | Zone 1 (Personal), Zone 2 (Team), Zone 3 (Enterprise) |
| `fsi_maxindividualshares` | Integer | Maximum individual shares per agent (default: 5) |
| `fsi_alloworgwidesharing` | Boolean | Whether organization-wide sharing is permitted |
| `fsi_allowpubliclink` | Boolean | Whether public internet links are permitted |
| `fsi_allowcrosstenant` | Boolean | Whether cross-tenant access is permitted |
| `fsi_approvedgroupsonly` | Boolean | Restrict sharing to approved security groups only |
| `fsi_isactive` | Boolean | Active policy flag |
| `fsi_createdby` | String(200) | Policy creator email |
| `fsi_createdat` | DateTime | Policy creation timestamp |
| `fsi_modifiedat` | DateTime | Last modification timestamp |
END REMOVED SECTION -->

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
| `fsi_cr_powerplatformadmin_sharingdetector` | Power Platform for Admins | Enumerate environments and discover agents for detection scans |

#### Configuration Steps

**Step 1: Create Dataverse Schema**

1. Install Python dependencies: `pip install -r scripts/requirements.txt`
2. Run the Dataverse schema setup script:
   ```bash
   python scripts/create_uasd_dataverse_schema.py \
       --tenant-id <tenant-id> \
       --environment-url https://org.crm.dynamics.com \
       --interactive
   ```
3. Verify tables created: `fsi_SharingViolation`, `fsi_SharingException`, `fsi_AgentSharingSetting`, `fsi_ApprovedSecurityGroup`, `fsi_SharingPolicy`

**Step 2: Set Environment Variables**

Run the environment variables setup script:
```bash
python scripts/create_uasd_environment_variables.py \
    --tenant-id <tenant-id> \
    --environment-url https://org.crm.dynamics.com \
    --interactive
```

Then configure values in Power Platform:

| Variable Name | Type | Example Value | Description |
|---------------|------|---------------|-------------|
| `fsi_UASD_DataverseUrl` | String | `https://org.crm.dynamics.com` | Dataverse environment URL |
| `fsi_UASD_HomeTenantId` | String | `12345678-1234-1234-1234-123456789012` | Your Entra tenant ID |
| `fsi_UASD_TeamsGroupId` | String | `87654321-4321-4321-4321-210987654321` | Teams group ID for alerts |
| `fsi_UASD_TeamsChannelId` | String | `19:abcd...@thread.tacv2` | Teams channel ID for alerts |
| `fsi_UASD_MaxIndividualShares` | Number | `5` | Threshold for individual share violations |
| `fsi_UASD_DefaultExceptionDays` | Number | `90` | Default exception duration (not currently referenced by flows; reserved for future use) |
| `fsi_UASD_RemediationDryRun` | String | `true` | Dry-run mode (true = no changes) |
| `fsi_UASD_ScanFrequencyHours` | Number | `24` | Detection scan interval in hours |
| `fsi_UASD_AutoRemediatePublicLink` | String | `false` | Automatically remediate public internet link violations |
| `fsi_UASD_SecurityApproverEmail` | String | `security@contoso.com` | Security team approver |
| `fsi_UASD_DataOwnerApproverEmail` | String | `dataowner@contoso.com` | Data owner approver |
| `fsi_UASD_ComplianceApproverEmail` | String | `compliance@contoso.com` | Compliance approver (required for Restricted data) |
| `fsi_UASD_ExpirationWarningDays` | Number | `7` | Days before expiration to send warning alerts (used by Expiration Monitor flow) |

**Step 3: Configure Connection References**

Run the connection references setup script:
```bash
python scripts/create_uasd_connection_references.py \
    --tenant-id <tenant-id> \
    --environment-url https://org.crm.dynamics.com \
    --interactive
```

Then bind each connection reference in Power Automate:

1. Open each flow in edit mode
2. Navigate to Data → Connection References
3. Create connections:
   - Dataverse (`fsi_cr_dataverse_sharingdetector`): Use Entra ID authentication
   - Teams (`fsi_cr_teams_sharingdetector`): Use current user authentication
   - Approvals (`fsi_cr_approvals_sharingdetector`): Use current user authentication
   - Power Platform for Admins (`fsi_cr_powerplatformadmin_sharingdetector`): Use current user authentication
4. Map connections to connection references

**Step 4: Build Flows in Power Automate**

Follow the step-by-step instructions in [docs/flow-configuration.md](docs/flow-configuration.md) to manually build each flow in Power Automate designer:
   - UASD-Detector-Scan-Agents → Scheduled Cloud Flow
   - UASD-Remediation-Apply-Sharing-Policy → Automated Cloud Flow
   - UASD-Exception-Approval-Workflow → Automated Cloud Flow
   - UASD-Exception-Expiration-Monitor → Scheduled Cloud Flow
   - UASD-Exception-Manager → Canvas App

**Step 5: Populate Approved Security Groups**

Add approved security groups to `fsi_ApprovedSecurityGroup` table:

> **Zone Classification:** Each approved security group must be assigned a zone classification (Zone 1: Personal, Zone 2: Team, Zone 3: Enterprise). The Remediation flow (Flow 2, Step 5) filters approved groups by zone when applying remediation. Zone classification is **not auto-detected** from the environment — it must be determined by your organization's environment governance model and assigned manually when populating this table. Map each Power Platform environment to a zone based on its intended use (e.g., personal developer environments → Zone 1, team/departmental → Zone 2, production/enterprise-wide → Zone 3).

```
Example Records:
┌──────────────────────────────────┬────────────────────────┬──────────┬───────────┐
│ fsi_entraidgroupid                │ fsi_displayname        │ fsi_zone │ fsi_is_   │
│                                  │                        │ classifi │ active    │
│                                  │                        │ cation   │           │
├──────────────────────────────────┼────────────────────────┼──────────┼───────────┤
│ aaaaaaaa-bbbb-cccc-dddd-eeee...  │ Zone2-PowerUsers       │ 100000002│ Yes       │
│ bbbbbbbb-cccc-dddd-eeee-ffff...  │ Zone3-EnterpriseUsers  │ 100000003│ Yes       │
│ cccccccc-dddd-eeee-ffff-0000...  │ Zone2-FinanceTeam      │ 100000002│ Yes       │
└──────────────────────────────────┴────────────────────────┴──────────┴───────────┘
```

**Step 6: Activate Flows**

1. Open each flow (Detector, Remediation, Exception Approval, Expiration Monitor)
2. Click "Turn on" to activate
3. Verify trigger configuration:
   - Detector: Confirm recurrence schedule (daily 06:00 UTC)
   - Remediation: Confirm Dataverse webhook on `fsi_SharingViolation`
   - Exception Approval: Confirm Dataverse webhook on `fsi_SharingException`
   - Expiration Monitor: Confirm recurrence schedule (daily 07:00 UTC)

**Step 7: Share Exception Manager App**

1. Navigate to Power Apps → Apps
2. Select Exception Manager app → Share
3. Share with security groups or users who should submit exceptions
4. Assign Dataverse security role with:
   - Read/Write on `fsi_SharingException`
   - Read on `fsi_SharingViolation`
   - Read on `fsi_AgentSharingSetting`
   - Read on `fsi_ApprovedSecurityGroup`

### Deployment Validation

**Test 1: Manual Detector Scan**

1. Open Detector flow → Run → Confirm success
2. Check Dataverse `fsi_AgentSharingSetting` table for scanned agents
3. Verify Teams channel received scan summary alert (if violations detected)

**Test 2: Violation Creation**

1. Create a test agent in Copilot Studio
2. Share with entire organization (violates ORG_WIDE_SHARING rule)
3. Run Detector flow → Verify violation record created in `fsi_SharingViolation` table
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

**Test 5: Exception Expiration Monitor**

1. Create an approved exception record with `fsi_expiresat` set to a past date (e.g., yesterday)
2. Run Expiration Monitor flow manually → Verify the record's `fsi_exceptionstatus` transitions to `100000003` (Expired)
3. Create an approved exception with `fsi_expiresat` set to 3 days from now (within the 7-day warning window)
4. Run Expiration Monitor flow → Verify Teams channel receives an "Exception Expiring Soon" adaptive card
5. Verify summary notification reports correct expired and warning counts

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
   - Entity name: `fsi_SharingViolation`
   - Message: 1 (Create) and 2 (Update)
   - Scope: 4 (Organization)
   - Filter: `fsi_violationstatus eq 100000000` AND `fsi_remediatedat eq null`
   - Filtering attributes: `fsi_violationstatus,fsi_remediatedat`
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
  <entity name="fsi_SharingViolation">
    <filter>
      <condition attribute="fsi_detectedat" operator="last-x-days" value="90"/>
    </filter>
    <order attribute="fsi_detectedat" descending="true"/>
  </entity>
</fetch>
```

**Export Format:**

Evidence files should include:
- Violation records with `fsi_evidencejson` (full sharing configuration snapshot)
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

### ORG_WIDE_SHARING (Code: 100000000)

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

### PUBLIC_INTERNET_LINK (Code: 100000001)

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

### UNAPPROVED_GROUP (Code: 100000002)

**Description:** Agent is shared with security groups not in the approved registry.

**Risk:** Unvetted user populations gain access, potentially including users with insufficient training, conflicting duties, or inappropriate access levels.

**Detection:** Security group GUIDs in agent sharing configuration not present in `fsi_ApprovedSecurityGroup` table with `fsi_isactive = true`.

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

### EXCESSIVE_INDIVIDUAL (Code: 100000003)

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

### CROSS_TENANT_ACCESS (Code: 100000004)

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

## Known Limitations

1. **~~Exception Expiration Monitoring Not Implemented~~ — Resolved in v1.0.2:** Build instructions for the `UASD-Exception-Expiration-Monitor` flow are now available in `docs/flow-configuration.md` Flow 4. The flow provides proactive 7-day warning alerts and automated `Expired` status transitions.

2. **`fsi_UASD_DefaultExceptionDays` Not Referenced:** The environment variable is provisioned but not currently consumed by any flow or Canvas App. Reserved for future use as a pre-populated default or enforced duration cap.

3. **`fsi_SharingPolicy` Table Reserved for Future Use:** The `fsi_SharingPolicy` table is defined in the Dataverse schema and provisioned by the setup scripts, but is not currently referenced by any flow, Canvas app, or governance script. It is intended for future per-zone policy enforcement. The table can be safely ignored until policy-driven remediation is implemented.

## Support and Maintenance

**Solution Version:** 1.0.2
**Release Date:** February 2026
**License:** MIT License

**Change Management:**
- Test all configuration changes in non-production environment first
- Document approved security group additions in change tickets
- Review remediation dry-run logs before disabling dry-run mode
- Coordinate exception expiration renewals with business owners 2 weeks in advance

**Version History:**
- **v1.0.2 (February 2026):** Added Flow 4 (UASD-Exception-Expiration-Monitor) build instructions; resolved Known Limitation #1 (exception expiration monitoring)
- **v1.0.1 (February 2026):** Replaced exported flow JSON with step-by-step documentation; fixed setup scripts
- **v1.0.0 (February 2026):** Initial release with 5 violation types, automated remediation, and exception management

---

*This solution supports compliance with FINRA 4511 (Supervision), SEC 17a-3/17a-4 (Recordkeeping), and SOX 302/404 (Internal Controls). Consult with your compliance and legal teams for applicability to your organization's regulatory requirements.*
