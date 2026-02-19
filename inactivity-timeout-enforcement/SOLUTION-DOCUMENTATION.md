# Securing AI Agent Sessions with Inactivity Timeout Controls
## Inactivity Timeout Enforcement (ITE)

**Version:** 1.0.3
**Solution Type:** Automated Compliance Detection and Monitoring
**Platform:** Microsoft Power Platform with Dataverse

---

## Executive Summary

### Problem Statement

Copilot Studio agents and Power Platform environments without properly configured inactivity timeout controls create significant security and compliance risks. When user sessions remain active indefinitely or exceed regulatory timeframes, they expose organizations to unauthorized access through unattended workstations, session hijacking, and regulatory violations.

**Risk Exposure:**
- **Unauthorized Access:** Active sessions on unattended workstations allow unauthorized users to impersonate legitimate users
- **Session Hijacking:** Extended session lifetimes increase attack windows for session token theft
- **Compliance Violations:** Failure to enforce timeout controls violates regulatory requirements (GLBA 501(b), SOX 302, FINRA 4511, NIST 800-53 AC-11/AC-12)
- **Data Exposure:** Prolonged sessions increase risk of data leakage through unattended terminals
- **Audit Gaps:** Inability to demonstrate timeout enforcement creates examination findings

### Solution Overview

The **Inactivity Timeout Enforcement (ITE)** solution provides continuous automated monitoring of Power Platform environment inactivity timeout configurations across your tenant. The solution evaluates timeout settings against zone-based governance policies, detects non-compliant configurations (including timeouts exceeding 120 minutes), and generates compliance reports with email alerting for immediate remediation.

**Key Capabilities:**
- **Continuous Detection:** Daily automated scans across all Power Platform environments
- **Zone-Based Policy Enforcement:** Different maximum timeout durations per governance zone (Personal/Team/Enterprise)
- **Compliance Status Tracking:** Compliant, Non-Compliant, and Unknown status classification with immutable audit trail
- **Guarded Alerting:** Email notifications sent only when issues detected (Non-Compliant or Unknown environments)
- **Error Handling:** Isolated per-environment error handling prevents scan failures from blocking tenant-wide visibility

**Business Value:**
- Reduce session-based security incidents through proactive timeout detection
- Eliminate manual audit overhead with automated compliance validation
- Support regulatory examinations with complete compliance history and evidence export
- Enable zone-based risk management with tailored timeout policies per environment tier

---

## Technical Details

### Architecture Overview

ITE operates as a single Power Automate cloud flow with daily scheduled execution. The architecture follows a policy-load, enumerate-evaluate, report pattern with per-environment error isolation and guarded notification.

```
┌─────────────────────────────────────────────────────────────────────┐
│             Inactivity Timeout Enforcement (ITE)                     │
│          Daily Compliance Detection & Monitoring                     │
└─────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │   Detect Inactivity Timeout   │
                    │   Non-Compliance Flow         │
                    │   (Daily 06:00 UTC)           │
                    └───────────────┬───────────────┘
                                    │
        ┌───────────────────────────┼───────────────────────────┐
        │                           │                           │
        ▼                           ▼                           ▼
┌───────────────┐          ┌─────────────────┐        ┌─────────────────┐
│  Load Policy  │          │   Enumerate     │        │   Evaluate      │
│  from         │──────────▶│  Environments   │────────▶│  Compliance     │
│  Dataverse    │          │  (BAP API)      │        │  Per Env        │
└───────────────┘          └─────────────────┘        └────────┬────────┘
                                                                │
                                                                ▼
                                                ┌───────────────────────────┐
                                                │  Write Compliance Record  │
                                                │  to Dataverse             │
                                                │  (Immutable)              │
                                                └───────────┬───────────────┘
                                                            │
        ┌───────────────────────────────────────────────────┼───────────────┐
        │                                                   │               │
        ▼                                                   ▼               ▼
┌───────────────┐                                  ┌─────────────┐  ┌──────────────┐
│  Query Non-   │                                  │  Query      │  │  Query       │
│  Compliant    │                                  │  Unknown    │  │  Compliant   │
│  Records      │                                  │  Records    │  │  Count       │
└───────┬───────┘                                  └──────┬──────┘  └──────┬───────┘
        │                                                 │                │
        └─────────────────────────┬───────────────────────┘                │
                                  │                                        │
                                  ▼                                        │
                          ┌───────────────┐                                │
                          │  Has Issues?  │                                │
                          │  (Guarded)    │                                │
                          └───────┬───────┘                                │
                                  │                                        │
                          Yes     │   No                                   │
                                  │   (skip email)                         │
                                  ▼                                        │
                        ┌─────────────────┐                                │
                        │  Send HTML      │                                │
                        │  Alert Email    │◀───────────────────────────────┘
                        │  (High Priority)│   (Include summary stats)
                        └─────────────────┘
```

### Solution Components

#### Detect Inactivity Timeout Non-Compliance Flow
**File:** `detect-inactivity-timeout-noncompliance.json`

**Purpose:** Continuous monitoring of inactivity timeout configurations across all Power Platform environments with zone-based policy evaluation.

**Trigger:**
- **Schedule:** Daily at 06:00 UTC (configurable)
- **Scope:** All Power Platform environments in the tenant
- **Type:** Recurrence trigger

**Compliance Logic:**

The flow implements three-state compliance classification:

| Compliance Status | Code | Detection Criteria | Result |
|-------------------|------|-------------------|--------|
| **Compliant** | 0 | Timeout enabled AND duration ≤ required maximum for zone | Pass |
| **Non-Compliant** | 1 | Timeout disabled OR duration > required maximum for zone | Fail |
| **Non-Compliant** | 1 | Timeout enabled but duration null (misconfigured) | Fail |
| **Unknown** | 2 | Missing policy for environment OR BAP API error | Unknown |

**Zone-Based Policy Enforcement:**

Environments are classified into governance zones with tailored maximum timeout durations:

| Zone | Classification | Recommended Max Timeout | Rationale |
|------|----------------|------------------------|-----------|
| **Zone 1** | Personal Development | 120 minutes | Individual developers with minimal data exposure |
| **Zone 2** | Team Collaboration | 90 minutes | Team environments with moderate data sensitivity |
| **Zone 3** | Enterprise Production | 60 minutes | Production environments with highest security requirements |

**Note:** All timeouts should not exceed 120 minutes (2 hours) per regulatory best practices (NIST 800-53 AC-11, FINRA 4511).

**Process Flow:**

1. **Initialization:**
   - Generate unique scan run ID (GUID) for correlation
   - Read `fsi_ITE_NotificationRecipients` via `@environmentVariables()` — Semicolon-separated email addresses
   - `fsi_ITE_ConcurrencyLimit` is defined as an environment variable but is **not** read via `@environmentVariables()` — concurrency is hardcoded at 5 (informational only)

2. **Policy Loading:**
   - Query `fsi_environmentpolicies` table from Dataverse
   - Extract environment-to-zone mappings with required maximum durations
   - Cache policy array in memory for fast lookup

3. **Environment Enumeration:**
   - Call BAP Admin API: `https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?$top=5000`
   - Use Managed Service Identity (MSI) authentication
   - Retrieve all environments in tenant
   - **Known Limitation:** The API call does not follow `@odata.nextLink` pagination. Tenants with more than 5000 environments may receive partial results, causing some environments to be silently excluded from compliance evaluation. For large tenants, consider extending the flow to handle pagination.

4. **Per-Environment Evaluation (Parallel):**
   - **Concurrency:** Hardcoded at 5 parallel evaluations (the `fsi_ITE_ConcurrencyLimit` environment variable is informational only)
   - For each environment:
     - Extract environment name (canonical ID) and display name
     - Resolve policy from cached array by environment ID
     - **If policy exists:**
       - Call BAP Privacy Settings API: `https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/{environmentName}/settings/privacy`
       - Parse `inactivityTimeoutEnabled` (boolean) and `inactivityTimeoutDuration` (ISO 8601)
       - Convert ISO 8601 duration to minutes (handles `PT60M`, `PT2H`, `PT1H30M` formats)
       - **Evaluate compliance:**
         - If timeout disabled → **Non-Compliant**
         - If timeout enabled but duration null → **Non-Compliant** (sentinel −1)
         - If timeout duration > required max → **Non-Compliant**
         - Otherwise → **Compliant**
       - Write immutable compliance record to `fsi_inactivitytimeoutcompliances` table
     - **If policy missing:**
       - Write **Unknown** compliance record
       - Log `MissingPolicy` error to `fsi_inactivitytimeouterrorlogs` table
     - **If BAP API error:**
       - Write **Unknown** compliance record
       - Log API error with HTTP status code to error log table
   - **Error Isolation:** Individual environment failures do not abort scan

5. **Summary Reporting:**
   - Query compliance records by scan run ID:
     - Non-Compliant records (`fsi_compliancestatus = 1`)
     - Unknown records (`fsi_compliancestatus = 2`)
     - Compliant count (`fsi_compliancestatus = 0`)
   - **Guarded Notification:** Only send email if Non-Compliant count > 0 OR Unknown count > 0
   - Build HTML email with:
     - Scan summary (compliant/non-compliant/unknown counts)
     - Detailed issues table (environment, zone, status, timeout enabled, actual duration, required max, notes)
   - Send email with High importance to configured recipients

6. **Error Handling:**
   - Outer scope catch for unexpected flow failures
   - Send CRITICAL email notification with flow run ID for investigation

**Configuration Parameters:**

| Variable Name | Type | Example Value | Description |
|---------------|------|---------------|-------------|
| `fsi_ITE_NotificationRecipients` | String | `security@contoso.com;compliance@contoso.com` | Semicolon-separated email addresses for compliance alerts |
| `fsi_ITE_ConcurrencyLimit` | Number | `5` | Parallel degree for environment evaluation (informational only — does not control runtime concurrency) |

> **Note:** The flow reads `fsi_ITE_NotificationRecipients` using Power Automate's `@environmentVariables()` function at initialization. `fsi_ITE_ConcurrencyLimit` is **not** read via `@environmentVariables()` — concurrency is hardcoded at 5. The Dataverse connection uses the connection reference — no separate URL variable is needed. Email send actions are guarded: if `fsi_ITE_NotificationRecipients` is empty, emails are silently skipped rather than causing a flow error.

**Email Alert Format:**

**Subject (Non-Compliant):**
```
[NON-COMPLIANT] Inactivity Timeout Compliance Scan — 3 issue(s) detected
```

**Body (HTML):**
```
Inactivity Timeout Compliance Scan Results

Scan Date: 2026-02-14T06:15:32Z
Scan Run ID: a1b2c3d4-e5f6-7890-abcd-ef1234567890

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Summary
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Compliant:        47
Non-Compliant:     2
Unknown:           1

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Issues Requiring Attention
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Environment         | Zone       | Status         | Timeout  | Actual  | Req Max | Notes
                    |            |                | Enabled  | (min)   | (min)   |
────────────────────┼────────────┼────────────────┼──────────┼─────────┼─────────┼───────────────────────
Finance-Prod        | Enterprise | Non-Compliant  | True     | 180     | 60      | Duration 180m exceeds maximum 60m
HR-Team-Sandbox     | Team       | Non-Compliant  | False    | 0       | 90      | Inactivity timeout is disabled
Legal-Dev           | Unassigned | Unknown        |          | 0       | 0       | No explicit policy found for environment
```

### Data Model

#### Dataverse Tables

**1. fsi_environmentpolicies (Environment Policies)**

Master registry of environment-to-zone mappings with required timeout policies.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_environmentid` | String(100) | Canonical Power Platform environment name (primary key for policy lookup) |
| `fsi_environmentdisplayname` | String(200) | Human-readable environment display name |
| `fsi_zone` | Choice | Governance zone: 1=Personal, 2=Team, 3=Enterprise |
| `fsi_requiredmaxduration` | Number | Required maximum inactivity timeout duration in minutes (e.g., 60, 90, 120) |

**Example Records:**
```
┌──────────────────────────────────┬────────────────────────┬──────┬─────────────────────┐
│ fsi_environmentid                │ fsi_environmentdisplay │ fsi_ │ fsi_requiredmax     │
│                                  │ name                   │ zone │ duration            │
├──────────────────────────────────┼────────────────────────┼──────┼─────────────────────┤
│ Default-aaaaaaaa-bbbb-cccc-dddd  │ Finance-Prod           │ 3    │ 60                  │
│ Development-bbbbbbbb-cccc-dddd   │ Legal-Dev              │ 1    │ 120                 │
│ Sandbox-cccccccc-dddd-eeee       │ HR-Team-Sandbox        │ 2    │ 90                  │
└──────────────────────────────────┴────────────────────────┴──────┴─────────────────────┘
```

**2. fsi_inactivitytimeoutcompliances (Compliance Records)**

Immutable audit trail of inactivity timeout compliance evaluations.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_inactivitytimeoutcomplianceid` | GUID | Primary key |
| `fsi_name` | String(200) | Auto-generated name: `{EnvironmentId} - {Timestamp}` |
| `fsi_environmentid` | String(100) | Canonical environment name |
| `fsi_environmentname` | String(200) | Environment display name |
| `fsi_zone` | Choice | Governance zone (from policy) |
| `fsi_inactivitytimeoutenabled` | Boolean | Whether inactivity timeout is enabled |
| `fsi_timeoutduration` | Number | Actual timeout duration in minutes (0 if disabled) |
| `fsi_requiredmaxduration` | Number | Required maximum duration from policy |
| `fsi_compliancestatus` | Choice | 0=Compliant, 1=Non-Compliant, 2=Unknown |
| `fsi_notes` | Memo | Human-readable compliance evaluation notes |
| `fsi_lastscandate` | DateTime | Scan execution timestamp (UTC) |
| `fsi_scanrunid` | String(50) | Correlation ID for batch scan (GUID) |

**Compliance Status Mapping:**
- **0 (Compliant):** Timeout enabled and duration ≤ required max
- **1 (Non-Compliant):** Timeout disabled OR duration > required max OR timeout enabled but duration null
- **2 (Unknown):** Missing policy OR BAP API error

**3. fsi_inactivitytimeouterrorlogs (Error Logs)**

Diagnostic logs for API errors and missing policy issues.

| Column Name | Type | Description |
|-------------|------|-------------|
| `fsi_inactivitytimeouterrorlogid` | GUID | Primary key |
| `fsi_name` | String(200) | Auto-generated name: `{ErrorType} - {EnvironmentId} - {Timestamp}` |
| `fsi_environmentid` | String(100) | Canonical environment name where error occurred |
| `fsi_errortype` | String(50) | Error classification: `MissingPolicy`, `Unauthorized`, `Forbidden`, `NotFound`, `Throttled`, `ActionError`, `HttpError` |
| `fsi_errorraw` | Memo | Raw error response from BAP API or policy lookup |
| `fsi_timestamp` | DateTime | Error occurrence timestamp (UTC) |

**Error Type Mapping:**
- **MissingPolicy:** No `fsi_environmentpolicies` record exists for environment
- **Unauthorized (401):** MSI lacks Power Platform Admin permissions
- **Forbidden (403):** Access denied to environment privacy settings
- **NotFound (404):** Environment not found or deleted
- **Throttled (429):** BAP API rate limit exceeded
- **ActionError:** Non-HTTP failure — Get_Privacy_Settings did not execute or returned 200 but a downstream action failed
- **HttpError:** Unrecognized HTTP status code from BAP Privacy Settings API

### Configuration and Prerequisites

#### Prerequisites

**Microsoft 365 Licensing:**
- Power Automate Premium (for cloud flow with HTTP actions and Dataverse)
- Power Platform Admin permissions (for BAP Admin API access)

**Permissions:**

| Role | Required For | Permission Level |
|------|--------------|-----------------|
| **Power Platform Admin** | Flow deployment, BAP API access | Admin or Global Admin |
| **Dataverse Admin** | Table creation, security roles | System Administrator |
| **Exchange Online Mailbox** | Email notification sending | Licensed mailbox for notification recipients |

**Service Connections:**

The solution requires the following connection references:

| Connection | API | Purpose |
|------------|-----|---------|
| `fsi_cr_dataverse_inactivitytimeout` | Dataverse | Read/write compliance records and policies |
| `fsi_cr_office365_inactivitytimeout` | Office 365 Outlook | Send email alerts for compliance issues |

**Managed Service Identity (MSI):**

The flow uses Managed Service Identity for BAP Admin API authentication. Ensure:
- MSI is enabled for the Power Platform environment
- MSI has **Power Platform Administrator** role assignment

#### Configuration Steps

**Step 1: Create Dataverse Tables**

Execute the following in Dataverse (via Power Apps maker portal → Tables → New table):

1. **Create `fsi_environmentpolicies` table:**
   - Display Name: Environment Policies
   - Plural Name: Environment Policies
   - Primary Column: `fsi_environmentid` (Text, 100 characters)
   - Add columns per Data Model section
   - Create choice field `fsi_zone`: 1=Personal, 2=Team, 3=Enterprise

2. **Create `fsi_inactivitytimeoutcompliances` table:**
   - Display Name: Inactivity Timeout Compliances
   - Plural Name: Inactivity Timeout Compliances
   - Primary Column: Auto-number (e.g., `ITC-{SEQNUM:5}`)
   - Add columns per Data Model section
   - Create choice field `fsi_compliancestatus`: 0=Compliant, 1=Non-Compliant, 2=Unknown

3. **Create `fsi_inactivitytimeouterrorlogs` table:**
   - Display Name: Inactivity Timeout Error Logs
   - Plural Name: Inactivity Timeout Error Logs
   - Primary Column: Auto-number (e.g., `ERR-{SEQNUM:5}`)
   - Add columns per Data Model section

**Step 2: Populate Environment Policies**

Add environment policies to `fsi_environmentpolicies` table with zone-based max durations:

```
Example Policy Records:
┌──────────────────────────────────┬────────────────────────┬──────┬─────────────────────┐
│ fsi_environmentid                │ fsi_environmentdisplay │ fsi_ │ fsi_requiredmax     │
│ (Power Platform Env Name)        │ name                   │ zone │ duration (minutes)  │
├──────────────────────────────────┼────────────────────────┼──────┼─────────────────────┤
│ Default-12345678-abcd-1234-abcd  │ Finance Production     │ 3    │ 60                  │
│ Sandbox-87654321-bcde-2345-bcde  │ Finance UAT            │ 2    │ 90                  │
│ Development-abcdefgh-cdef-3456   │ Developer - John Doe   │ 1    │ 120                 │
│ Default-aaaaaaaa-bbbb-cccc-dddd  │ HR Production          │ 3    │ 60                  │
└──────────────────────────────────┴────────────────────────┴──────┴─────────────────────┘
```

**Note:** To get canonical environment names, navigate to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com) → Environments → Select environment → Settings → Details. The **Environment URL** contains the canonical name.

**Step 3: Import Solution**

1. Download the flow JSON: `detect-inactivity-timeout-noncompliance.json`
2. Navigate to Power Platform Admin Center → Environments
3. Select your governance environment (recommended: dedicated governance environment)
4. Navigate to Solutions → Import
5. Import the JSON file as a cloud flow

**Step 4: Configure Connection References**

1. Open flow in edit mode
2. Navigate to Data → Connection References
3. Create connections:
   - **Dataverse:** Use Entra ID authentication (service account or current user)
   - **Office 365 Outlook:** Use current user authentication
4. Map connections to connection references:
   - `fsi_cr_dataverse_inactivitytimeout` → Dataverse connection
   - `fsi_cr_office365_inactivitytimeout` → Office 365 connection

**Step 5: Set Environment Variables**

Create environment variables in Power Platform:

| Variable Name | Type | Example Value | Description |
|---------------|------|---------------|-------------|
| `fsi_ITE_NotificationRecipients` | String | `security@contoso.com;compliance@contoso.com` | Semicolon-separated email addresses |
| `fsi_ITE_ConcurrencyLimit` | Number | `5` | Parallel environment evaluation degree (informational only — does not control runtime concurrency) |

**Step 6: Configure Managed Service Identity**

1. Enable MSI for the Power Platform environment:
   - Navigate to Azure Portal → Managed Identities → Create
   - Assign identity to Power Platform environment
2. Grant Power Platform Administrator role to MSI:
   - Navigate to Microsoft 365 Admin Center → Roles → Power Platform Administrator
   - Add MSI service principal as member

**Step 7: Activate Flow**

1. Open flow in edit mode
2. Click "Turn on" to activate
3. Verify trigger configuration: Daily recurrence at 06:00 UTC
4. Save flow

### Deployment Validation

**Test 1: Manual Flow Run**

1. Open flow → Run → Confirm success
2. Check Dataverse `fsi_inactivitytimeoutcompliances` table for compliance records
3. Verify scan run ID is consistent across all records for this execution
4. Check email inbox for notification (only sent if issues detected)

**Test 2: Policy Resolution**

1. Create test policy in `fsi_environmentpolicies` table:
   - Environment ID: `Test-Environment-12345`
   - Display Name: `Test Environment`
   - Zone: `2` (Team)
   - Required Max Duration: `90` minutes
2. Verify flow resolves policy during next run
3. Check compliance record has correct zone and required max values

**Test 3: Compliance Detection (Non-Compliant Scenario)**

1. Identify test environment with timeout > 120 minutes (or disabled)
2. Add policy for test environment to `fsi_environmentpolicies` table (required max: 120)
3. Run flow manually
4. Verify compliance record status = **Non-Compliant** (1)
5. Verify email notification sent with environment details

**Test 4: Error Handling (Missing Policy)**

1. Remove policy for a known environment from `fsi_environmentpolicies` table
2. Run flow manually
3. Verify compliance record status = **Unknown** (2)
4. Check `fsi_inactivitytimeouterrorlogs` table for `MissingPolicy` error entry
5. Verify email notification includes Unknown environment in issues table

### Operational Guidance

#### Daily Operations

**Monitoring:**
- Review email alerts each morning after 06:00 UTC scan
- Prioritize Non-Compliant environments (timeout disabled or exceeding max)
- Investigate Unknown environments (missing policies or API errors)
- Target: Resolve all Non-Compliant environments within 2 business days

**Policy Management:**
- Add `fsi_environmentpolicies` records for new environments within 24 hours of creation
- Review zone classifications quarterly (environments may change purpose/tier)
- Adjust required max durations based on regulatory guidance updates
- Document policy exceptions with business justification

**Compliance Remediation:**

For **Non-Compliant** environments (timeout disabled):
1. Navigate to [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)
2. Environments → Select environment → Settings → Privacy + Security
3. Enable **Inactivity timeout**
4. Set duration to required maximum per zone (Zone 1: 120, Zone 2: 90, Zone 3: 60 minutes)
5. Verify next scan shows **Compliant** status

For **Non-Compliant** environments (timeout exceeds max):
1. Navigate to Power Platform Admin Center → Environment Settings
2. Reduce **Inactivity timeout** to required maximum or lower
3. Example: Zone 3 (Enterprise) requires ≤ 60 minutes → Set to 60 minutes
4. Verify next scan shows **Compliant** status

For **Unknown** environments (missing policy):
1. Determine appropriate zone classification (Personal/Team/Enterprise)
2. Add policy record to `fsi_environmentpolicies` table:
   - Environment ID: Canonical environment name (from PPAC)
   - Display Name: Environment display name
   - Zone: 1/2/3 (Personal/Team/Enterprise)
   - Required Max Duration: per zone (Zone 1: 120, Zone 2: 90, Zone 3: 60 minutes)
3. Verify next scan evaluates environment and removes **Unknown** status

For **Unknown** environments (API error):
1. Check `fsi_inactivitytimeouterrorlogs` table for error type
2. **Unauthorized (401):** Verify MSI has Power Platform Administrator role
3. **Forbidden (403):** Verify MSI permissions on specific environment
4. **NotFound (404):** Environment may have been deleted → Remove policy record
5. **Throttled (429):** BAP API rate limit exceeded → Contact Microsoft Support
6. **ActionError:** Non-HTTP failure or downstream action error → Investigate flow run history for action-level failures
7. **HttpError:** Unrecognized HTTP status code → Investigate flow run history for unexpected API responses

#### Troubleshooting

**Issue: Flow fails with "Unauthorized" error**

**Cause:** Managed Service Identity lacks Power Platform Administrator role

**Resolution:**
1. Navigate to Microsoft 365 Admin Center → Roles → Power Platform Administrator
2. Add MSI service principal as member
3. Wait 15 minutes for role propagation
4. Re-run flow to verify success

**Issue: Email notifications not sent**

**Cause:** Guarded notification logic (no issues detected) or connection error

**Resolution:**
1. Verify Non-Compliant count > 0 OR Unknown count > 0 in scan run
   - If all environments Compliant → No email sent (expected behavior)
   - If issues exist but no email → Check Office 365 connection
2. Open flow → Data → Connection References → Verify Office 365 connection valid
3. Test Office 365 connection with manual "Send Email" action
4. Verify `fsi_ITE_NotificationRecipients` environment variable contains valid email addresses

**Issue: Compliance records show incorrect zone**

**Cause:** Policy record has wrong zone classification or environment ID mismatch

**Resolution:**
1. Query `fsi_environmentpolicies` table for affected environment
2. Verify `fsi_environmentid` matches canonical environment name (not display name)
3. Correct zone classification if incorrect (1=Personal, 2=Team, 3=Enterprise)
4. Update policy record and re-run flow to verify correct zone

**Issue: ISO 8601 duration parsing error**

**Cause:** Unsupported duration format from BAP Privacy Settings API

**Resolution:**
1. Check flow run history for `Parse_Duration_Minutes` action failure
2. Review `fsi_errorraw` field in `fsi_inactivitytimeouterrorlogs` table for actual duration string
3. Supported formats: `PT60M` (60 minutes), `PT2H` (2 hours), `PT1H30M` (1 hour 30 minutes)
4. If unsupported format → Log support case with Microsoft for BAP API

**Issue: Concurrency throttling (HTTP 429)**

**Cause:** BAP Admin API rate limit exceeded due to high concurrency

**Resolution:**
1. Wait and retry — the flow includes an exponential retry policy (3 retries, 30s interval, 5m max) that handles transient 429 errors automatically
2. If throttling persists across multiple runs → Contact Microsoft Support for a BAP Admin API rate limit increase
3. Note: The `fsi_ITE_ConcurrencyLimit` environment variable does not control runtime concurrency (loop concurrency is hardcoded to 5 in the flow definition)

#### Audit and Evidence Export

**Evidence Collection:**

For regulatory examinations, export compliance records and policy configurations:

```sql
-- Dataverse FetchXML query for compliance evidence (last 90 days)
<fetch>
  <entity name="fsi_inactivitytimeoutcompliances">
    <filter>
      <condition attribute="fsi_lastscandate" operator="last-x-days" value="90"/>
    </filter>
    <order attribute="fsi_lastscandate" descending="true"/>
  </entity>
</fetch>
```

**Export Format:**

Evidence files should include:
- Compliance records with status, actual duration, required max, notes (CSV or Excel)
- Policy configurations from `fsi_environmentpolicies` table (CSV or Excel)
- Error logs from `fsi_inactivitytimeouterrorlogs` table (CSV or Excel)
- Email notification history (forward alerts to compliance archive mailbox)

**Retention:**

- Compliance records: Retain for 7 years (SEC 17a-4 requirement)
- Policy configurations: Retain for 7 years (audit trail requirement)
- Error logs: Retain for 3 years (operational history)
- Email notifications: Retain for 3 years (compliance evidence)

---

## Appendix: Compliance Status Reference

### Compliant (Code: 0)

**Description:** Environment has inactivity timeout enabled with duration at or below required maximum for its zone.

**Criteria:**
- `inactivityTimeoutEnabled = true`
- `timeoutDuration ≤ requiredMaxDuration`

**Example:**
```
Environment: Finance Production
Zone: 3 (Enterprise)
Timeout Enabled: true
Actual Duration: 55 minutes
Required Max: 60 minutes
Status: Compliant
Notes: Compliant: 55m within 60m maximum
```

### Non-Compliant (Code: 1)

**Description:** Environment has inactivity timeout disabled OR timeout duration exceeds required maximum for its zone.

**Criteria:**
- `inactivityTimeoutEnabled = false OR null` (timeout disabled or not set)
- OR `timeoutDuration > requiredMaxDuration` (exceeds maximum)

**Example 1 (Timeout Disabled):**
```
Environment: HR Team Sandbox
Zone: 2 (Team)
Timeout Enabled: false
Actual Duration: 0 minutes
Required Max: 90 minutes
Status: Non-Compliant
Notes: Inactivity timeout is disabled
```

**Example 2 (Exceeds Maximum):**
```
Environment: Legal Production
Zone: 3 (Enterprise)
Timeout Enabled: true
Actual Duration: 240 minutes
Required Max: 60 minutes
Status: Non-Compliant
Notes: Duration 240m exceeds maximum 60m
```

**Remediation:**
- **If disabled:** Enable inactivity timeout in Power Platform Admin Center
- **If exceeds max:** Reduce timeout duration to required maximum or lower

### Unknown (Code: 2)

**Description:** Unable to evaluate compliance due to missing policy or BAP API error.

**Criteria:**
- No `fsi_environmentpolicies` record exists for environment
- OR BAP Privacy Settings API call failed

**Example 1 (Missing Policy):**
```
Environment: Developer Sandbox
Zone: null
Timeout Enabled: (null)
Actual Duration: 0 minutes
Required Max: 0 minutes
Status: Unknown
Notes: No explicit policy found for environment
Error Log: MissingPolicy - No fsi_environmentpolicy row exists for EnvironmentName: Development-abc123
```

**Example 2 (API Error):**
```
Environment: External Sandbox
Zone: 2 (from policy)
Timeout Enabled: (null)
Actual Duration: 0 minutes
Required Max: 120 minutes
Status: Unknown
Notes: BAP API call failed: Forbidden
Error Log: Forbidden (403) - Access denied to privacy settings for environment
```

**Remediation:**
- **Missing Policy:** Add policy record to `fsi_environmentpolicies` table with appropriate zone and required max
- **API Error:** Investigate error type in `fsi_inactivitytimeouterrorlogs` and resolve permissions or API issues

---

## Appendix: ISO 8601 Duration Parsing

The solution parses ISO 8601 duration strings from the BAP Privacy Settings API response (`inactivityTimeoutDuration` field) and converts them to minutes for compliance evaluation.

**Supported Formats:**

| Format | Example | Parsed Value (minutes) | Description |
|--------|---------|------------------------|-------------|
| `PTnM` | `PT60M` | 60 | Minutes only |
| `PTnH` | `PT2H` | 120 | Hours only (converted to minutes: 2 × 60 = 120) |
| `PTnHnM` | `PT1H30M` | 90 | Hours + minutes (1 × 60 + 30 = 90) |

**Parsing Logic:**

1. **If timeout disabled:** Return `0` minutes
2. **If format contains both H and M:** Extract hours and minutes, convert to total minutes
3. **If format contains only H:** Extract hours, multiply by 60
4. **If format contains only M:** Extract minutes directly
5. **If timeout enabled but duration is null:** Return `-1` sentinel (treated as Non-Compliant by `Evaluate_Compliance`)
6. **If format is unrecognized:** Parsing fails with a runtime error (caught by `Scope_BAP_API_Catch` and classified as `ActionError`)

**Example Conversions:**

```
Input: "PT60M"   → Output: 60 minutes  (1 hour)
Input: "PT120M"  → Output: 120 minutes (2 hours)
Input: "PT2H"    → Output: 120 minutes (2 hours)
Input: "PT1H30M" → Output: 90 minutes  (1.5 hours)
Input: "PT0M"    → Output: 0 minutes   (disabled or zero)
```

---

## Appendix: Regulatory Alignment

The Inactivity Timeout Enforcement solution supports compliance with the following regulatory requirements:

### GLBA 501(b) — Safeguards Rule

**Requirement:** Financial institutions must implement administrative, technical, and physical safeguards to protect customer information, including access controls and session management.

**ITE Support:**
- Enforces inactivity timeout controls across all Power Platform environments
- Provides audit trail of timeout configurations and compliance status
- Generates evidence of continuous monitoring for regulatory examinations

### SOX 302 — Internal Controls over Financial Reporting

**Requirement:** Management must establish and maintain adequate internal controls to ensure reliability of financial reporting, including IT controls for session management.

**ITE Support:**
- Zone-based policy enforcement ensures financial production environments (Zone 3) meet 60-minute maximum timeout
- Immutable compliance records provide audit trail for internal control effectiveness
- Daily monitoring enables timely detection of control deficiencies

### FINRA 4511 — Supervision

**Requirement:** Member firms must establish and maintain a system to supervise the activities of associated persons, including technology controls for unauthorized access prevention.

**ITE Support:**
- Continuous monitoring ensures inactivity timeout controls remain effective
- Non-compliant environment detection prevents unauthorized access through unattended workstations
- Email alerting enables timely supervisory review and remediation

### NIST 800-53 AC-11 — Session Lock

**Requirement:** Information systems must prevent further access by initiating a session lock after a period of inactivity (recommended: ≤ 15-120 minutes based on risk).

**ITE Support:**
- Enforces maximum 60-minute timeout for production environments (Zone 3)
- Zone-based tiering allows risk-appropriate timeout durations (Zone 1: 120, Zone 2: 90, Zone 3: 60 minutes)
- Compliance detection identifies disabled or excessive timeouts

### NIST 800-53 AC-12 — Session Termination

**Requirement:** Information systems must automatically terminate user sessions after a defined condition or trigger.

**ITE Support:**
- Validates inactivity timeout termination is enabled across all environments
- Ensures termination occurs within regulatory timeframes (≤ 120 minutes)
- Provides evidence of automated session termination enforcement

---

## Support and Maintenance

**Solution Version:** 1.0.3
**Release Date:** February 2026
**License:** MIT License

**Change Management:**
- Test environment policy changes in non-production first
- Document zone classification decisions in change tickets
- Review compliance trends monthly to identify recurring issues
- Coordinate timeout policy updates with user communication (advance notice recommended)

**Version History:**
- **v1.0.3 (February 2026):** Fix post-loop reporting `runAfter` conditions, replace `ParseError` with `ActionError`/`HttpError` error types, fix `Create_Unknown_APIErrorRecord` setting `fsi_inactivitytimeoutenabled` to `null`, add `-1` sentinel for null `inactivityTimeoutDuration` (Non-Compliant), add `$top=5000` to `List_Environments` URI, add partial-results note to `Scope_Catch` error email
- **v1.0.2 (February 2026):** Fix zone-mapping crash on null `fsi_zone`, fix false Compliant status on null `inactivityTimeoutEnabled`, fix inverted zone timeout recommendations in documentation, remove phantom `fsi_ITE_ScanFrequencyHours` variable, revert `ConcurrencyLimit` to hardcoded value (5) — `fsi_ITE_ConcurrencyLimit` is informational only
- **v1.0.1 (February 2026):** Wire `NotificationRecipients` to `@environmentVariables()`, add recipient guard on email actions, add exponential retry policy to HTTP actions, map zone integers to friendly names, remove vestigial `DataverseUrl` variable (note: `ConcurrencyLimit` was also wired to `@environmentVariables()` in this release but reverted to hardcoded in v1.0.2)
- **v1.0.0 (February 2026):** Initial release with zone-based policy enforcement, daily compliance detection, and guarded email alerting

---

*This solution supports compliance with GLBA 501(b), SOX 302, FINRA 4511, and NIST 800-53 AC-11/AC-12. Consult with your compliance and legal teams for applicability to your organization's regulatory requirements.*
