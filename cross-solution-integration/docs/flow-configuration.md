# Flow Configuration Guide

> **Solution:** Cross-Solution Integration
> **Version:** v1.0.1

This document provides step-by-step instructions for manually building the two Power Automate cloud flows required by the Cross-Solution Integration layer. These flows automate the daily Compliance Dashboard feed from Tier 2 solutions and the environment initialization cascade from ELM provisioning events.

---

## Connection References

Both flows use the same two connection references:

| Connection Reference | Display Name | Connector | Purpose |
|---------------------|-------------|-----------|---------|
| `fsi_cr_dataverse_int` | Dataverse — Integration | Microsoft Dataverse | Read validation history, upsert assessments, log errors |
| `fsi_cr_teams_int` | Teams — Integration | Microsoft Teams | Post summary/notification messages to governance channel |

Create these connection references in your solution before building the flows. Use a service account with Dataverse read/write access to all `fsi_*` tables and Teams channel posting permissions.

---

## Environment Variables

### CD-SolutionFeedCollector Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `fsi_INT_ControlGuid_1_7` | String | Control master GUID for Control 1.7 (ACV feed) |
| `fsi_INT_ControlGuid_1_23` | String | Control master GUID for Control 1.23 (SSC/CAA feed) |
| `fsi_INT_ControlGuid_1_11` | String | Control master GUID for Control 1.11 (SSC/CAA feed) |
| `fsi_INT_ControlGuid_3_8` | String | Control master GUID for Control 3.8 (AAM feed) |
| `fsi_INT_ControlGuid_1_8` | String | Control master GUID for Control 1.8 (CMM feed) |
| `fsi_INT_ControlGuid_1_14` | String | Control master GUID for Control 1.14 (FUS feed) |
| `fsi_INT_ControlGuid_1_18` | String | Control master GUID for Control 1.18 (CAA feed) |
| `fsi_INT_TeamsGroupId` | String | Microsoft 365 group ID for the governance Teams channel |
| `fsi_INT_TeamsChannelId` | String | Channel ID for sync summary notifications |

To find control master GUIDs, query the `fsi_controlmasters` table in Dataverse for the corresponding control numbers.

### ELM-SolutionInitializer Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `fsi_INT_TeamsGroupId` | String | Microsoft 365 group ID for the governance Teams channel |
| `fsi_INT_TeamsChannelId` | String | Channel ID for initialization notifications |

---

## Flow 1: CD-SolutionFeedCollector

**Purpose:** Daily automated feed from 6 Tier 2 governance solutions (ACV, SSC, AAM, CMM, FUS, CAA) into Compliance Dashboard `fsi_controlassessments` records. Each solution's latest validation result is queried, translated to a status/score, and upserted as a control assessment.

**Schedule:** Daily at 6:30 AM UTC (recommended 30 minutes after Tier 2 daily scans complete).

### Trigger

| Property | Value |
|----------|-------|
| Type | Recurrence |
| Frequency | Day |
| Interval | 1 |
| Start Time | `2026-02-11T06:30:00Z` (adjust to your environment) |
| Time Zone | UTC |
| Concurrency | Single instance |

### Step-by-Step Build Instructions

#### Step 1 — Initialize Variables

1. **Initialize variable** — `RunId`
   - Name: `RunId`
   - Type: String
   - Value: `guid()` expression

2. **Initialize variable** — `SyncResults`
   - Name: `SyncResults`
   - Type: Array
   - Value: `[]` (empty array)

#### Step 2 — Validate Parameters

Add a **Condition** action to validate that all 7 control GUID environment variables are non-empty.

- **Condition (OR):** Any of the following is true:
  - `fsi_INT_ControlGuid_1_7` equals `""`
  - `fsi_INT_ControlGuid_1_23` equals `""`
  - `fsi_INT_ControlGuid_1_11` equals `""`
  - `fsi_INT_ControlGuid_3_8` equals `""`
  - `fsi_INT_ControlGuid_1_8` equals `""`
  - `fsi_INT_ControlGuid_1_14` equals `""`
  - `fsi_INT_ControlGuid_1_18` equals `""`

- **If yes:** Add a **Terminate** action
  - Status: Failed
  - Code: `MissingConfiguration`
  - Message: `One or more required control GUID parameters are empty. Configure all fsi_INT_ControlGuid_* parameters before activating this flow.`

- **If no:** Leave empty (continue to sync scopes)

#### Step 3 — Sync Scopes (6 Parallel Scopes)

After the Validate_Parameters condition, add 6 **Scope** actions. Scopes for ACV, SSC, AAM, CMM, and FUS all run in parallel after Validate_Parameters succeeds. CAA runs after the SSC result is appended (see dependency note below).

Each scope follows the same pattern with solution-specific differences in the source table, status mapping, and target controls. Set a **10-minute timeout** on each scope.

Configure **exponential retry** on all Dataverse actions: 3 retries, 10s initial interval, 1-minute maximum.

---

##### Scope: Sync_ACV (Control 1.7)

**Source table:** `fsi_auditvalidationhistories`

1. **List rows** — Query ACV Latest
   - Table: `fsi_auditvalidationhistories`
   - Filter: `fsi_validationtype eq 'Orchestrator'`
   - Order by: `fsi_timestamp desc`
   - Select: `fsi_severity,fsi_runid,fsi_timestamp`
   - Top count: `1`

2. **Condition** — ACV Has Records
   - Check: `length(body('Query_ACV_Latest')?['value'])` is greater than `0`

3. **If yes → Compose** — Map ACV Status
   - Use the severity-based mapping:

   | Severity | Status | Score |
   |----------|--------|-------|
   | 1 (Info) | 1 (Compliant) | 100 |
   | 2 or 3 (Warning/Error) | 2 (Non-Compliant) | 50 |
   | Other | 3 (Critical) | 0 |

4. **If yes → Upsert Assessment** — Check for existing assessment today, then create or update:
   - **List rows** — Check existing `fsi_controlassessments` where `_fsi_controlmasterid_value` equals the `fsi_INT_ControlGuid_1_7` parameter and `fsi_assessmentdate` is today
   - **If exists → Update row:** Set `fsi_status`, `fsi_score`, `fsi_notes` (include ACV version, run ID, severity), `fsi_nextreviewdate` = tomorrow
   - **If not exists → Add row:** Create with `fsi_controlmasterid` lookup bound to the control GUID, plus the same fields as update, plus `fsi_assessmentdate` = `utcNow()`

---

##### Scope: Sync_SSC (Controls 1.23 and 1.11)

**Source table:** `fsi_validationhistories`

1. **List rows** — Query SSC Latest
   - Table: `fsi_validationhistories`
   - Filter: `fsi_validationtype eq 'Orchestrator'`
   - Order by: `fsi_timestamp desc`
   - Select: `fsi_severity,fsi_runid,fsi_timestamp`
   - Top count: `1`

2. **Condition** — SSC Has Records (same length check)

3. **If yes → Compose** — Map SSC Status (same severity mapping as ACV)

4. **If yes → Upsert for Control 1.23:**
   - Check existing assessment for `fsi_INT_ControlGuid_1_23` + today
   - Update or create with notes: `Automated: SSC v1.0.0. Run: {runId}. Severity: {severity}. Control 1.23 (dual-feed with CAA).`

5. **If yes → Upsert for Control 1.11** (sequential after 1.23):
   - Check existing assessment for `fsi_INT_ControlGuid_1_11` + today
   - Update or create with notes: `Automated: SSC v1.0.0. Run: {runId}. Severity: {severity}. Control 1.11 (dual-feed with CAA).`

---

##### Scope: Sync_AAM (Control 3.8)

**Source table:** `fsi_accessvalidationhistories`

1. **List rows** — Query AAM Latest
   - Table: `fsi_accessvalidationhistories`
   - Order by: `fsi_timestamp desc`
   - Select: `fsi_overall_status,fsi_runid,fsi_timestamp`
   - Top count: `1`

2. **Condition** — AAM Has Records

3. **If yes → Compose** — Map AAM Status (string-based mapping):

   | fsi_overall_status | Status | Score |
   |-------------------|--------|-------|
   | `compliant` (case-insensitive) | 1 (Compliant) | 100 |
   | `warning` (case-insensitive) | 2 (Non-Compliant) | 50 |
   | Other | 3 (Critical) | 0 |

4. **If yes → Upsert Assessment** for `fsi_INT_ControlGuid_3_8` (same upsert pattern as ACV)

---

##### Scope: Sync_CMM (Control 1.8)

**Source table:** `fsi_moderationvalidationhistories`

1. **List rows** — Query CMM Latest
   - Table: `fsi_moderationvalidationhistories`
   - Order by: `fsi_timestamp desc`
   - Select: `fsi_compliant_count,fsi_total_agents,fsi_runid,fsi_timestamp`
   - Top count: `1`

2. **Condition** — CMM Has Records

3. **If yes → Compose** — Map CMM Status (compliance-rate-based mapping):
   - Calculate `complianceRate = (fsi_compliant_count / fsi_total_agents) × 100`
   - Handle edge case: if `fsi_total_agents` is 0 or null, set status = 4 (Not Assessed), score = null

   | Compliance Rate | Status | Score |
   |----------------|--------|-------|
   | ≥ 100% | 1 (Compliant) | Rounded rate |
   | ≥ 80% | 2 (Non-Compliant) | Rounded rate |
   | < 80% | 3 (Critical) | Rounded rate |
   | No agents | 4 (Not Assessed) | null |

4. **If yes → Upsert Assessment** for `fsi_INT_ControlGuid_1_8`
   - Notes include: `Compliance: {compliantCount}/{totalAgents} agents.`

---

##### Scope: Sync_FUS (Control 1.14)

**Source table:** `fsi_fileupload_validationhistories`

1. **List rows** — Query FUS Latest
   - Table: `fsi_fileupload_validationhistories`
   - Order by: `fsi_timestamp desc`
   - Select: `fsi_compliance_rate,fsi_runid,fsi_timestamp`
   - Top count: `1`

2. **Condition** — FUS Has Records

3. **If yes → Compose** — Map FUS Status:

   | fsi_compliance_rate | Status | Score |
   |--------------------|--------|-------|
   | null | 3 (Critical) | 0 |
   | ≥ 100 | 1 (Compliant) | Rounded rate |
   | ≥ 80 | 2 (Non-Compliant) | Rounded rate |
   | < 80 | 3 (Critical) | Rounded rate |

4. **If yes → Upsert Assessment** for `fsi_INT_ControlGuid_1_14`
   - Notes include: `Compliance rate: {complianceRate}%.`

---

##### Scope: Sync_CAA (Controls 1.11, 1.23, 1.18)

> **Dependency:** This scope runs after `Append_SSC_Result` succeeds (i.e., after the SSC scope completes), because CAA writes to the same controls (1.11 and 1.23) as SSC and uses a dual-feed worst-of-two merge strategy.

**Source table:** `fsi_capolicyvalidationhistories`

1. **List rows** — Query CAA Latest
   - Table: `fsi_capolicyvalidationhistories`
   - Filter: `fsi_validationtype eq 'Orchestrator'`
   - Order by: `fsi_timestamp desc`
   - Select: `fsi_severity,fsi_runid,fsi_timestamp`
   - Top count: `1`

2. **Condition** — CAA Has Records

3. **If yes → Compose** — Map CAA Status (same severity mapping as ACV/SSC)

4. **If yes → Upsert for Control 1.11** (dual-feed worst-of-two):
   - Check existing assessment for `fsi_INT_ControlGuid_1_11` + today
   - Select includes: `fsi_controlassessmentid,fsi_status,fsi_score`
   - **If exists → Update** using worst-of-two merge logic:
     - If existing status = 4 (Not Assessed), use CAA status
     - If CAA status = 4 (Not Assessed), keep existing status
     - Otherwise, keep the **higher** status value (worse condition) and **lower** score
   - **If not exists → Create** with CAA status directly (primary feed, dual-feed with SSC)

5. **If yes → Upsert for Control 1.23** (same worst-of-two pattern as 1.11)

6. **If yes → Upsert for Control 1.18** (simple upsert, no dual-feed):
   - Standard check-exists → update or create pattern
   - Notes: `Control 1.18 (secondary).`

---

#### Step 4 — Per-Scope Error Handling and Result Collection

After each sync scope, add two parallel actions configured to run on different outcomes:

1. **Append to array variable** — Append result to `SyncResults`
   - Runs on: Succeeded, Failed, TimedOut
   - Value: `"{SOLUTION}: Synced"` or `"{SOLUTION}: Failed"` based on scope status
   - Expression: `if(equals(actions('Sync_{SOL}')?['status'], 'Succeeded'), 'Synced', 'Failed')`

2. **Add a row (Dataverse)** — Log error to `fsi_integrationerrorlogs`
   - Runs on: Failed, TimedOut, Skipped
   - Fields:
     - `fsi_name`: `Sync_{SOL} failure — {utcNow()}`
     - `fsi_solution`: Solution abbreviation (ACV, SSC, AAM, CMM, FUS, CAA)
     - `fsi_runid`: `RunId` variable
     - `fsi_errormessage`: `actions('Sync_{SOL}')?['error']?['message']`
     - `fsi_timestamp`: `utcNow()`

#### Step 5 — Teams Summary Notification

After all 6 Append_*_Result actions succeed, add a **Post message in a chat or channel** action:

- Connection: `fsi_cr_teams_int`
- Post as: Flow bot
- Post in: Channel
- Team: `fsi_INT_TeamsGroupId` parameter
- Channel: `fsi_INT_TeamsChannelId` parameter
- Message body (HTML):
  ```html
  <p><strong>📊 Compliance Dashboard Feed Complete</strong></p>
  <p>Run ID: {RunId}<br/>
  Timestamp: {utcNow()}<br/>
  Results: {join(SyncResults, ', ')}</p>
  ```

Add a **Compose** action that runs if the Teams message fails:
- Runs on: Failed, TimedOut, Skipped
- Value: `Teams summary notification failed — all solution syncs completed successfully. Operators should monitor the fsi_integrationerrorlogs table and SyncResults variable for per-solution sync status.`

### Status Mapping Reference

See [STATUS_MAPPING.md](STATUS_MAPPING.md) for the complete per-solution status translation logic.

### Data Flow Diagram

```
Tier 2 Solutions                    This Flow                     Compliance Dashboard
─────────────────                   ──────────                    ────────────────────
ACV → fsi_auditvalidationhistories ──→ Map Severity ──→ Upsert ──→ fsi_controlassessments (1.7)
SSC → fsi_validationhistories ──────→ Map Severity ──→ Upsert ──→ fsi_controlassessments (1.23, 1.11)
AAM → fsi_accessvalidationhistories → Map Status   ──→ Upsert ──→ fsi_controlassessments (3.8)
CMM → fsi_moderationvalidationhistories → Map Rate ──→ Upsert ──→ fsi_controlassessments (1.8)
FUS → fsi_fileupload_validationhistories → Map Rate → Upsert ──→ fsi_controlassessments (1.14)
CAA → fsi_capolicyvalidationhistories → Map Severity → Upsert ──→ fsi_controlassessments (1.11, 1.23, 1.18)
```

---

## Flow 2: ELM-SolutionInitializer

**Purpose:** Child flow triggered when Environment Lifecycle Management (ELM) logs a successful provisioning event. Cascades to downstream solution registration by auto-registering the newly provisioned environment in the ACV `fsi_environmentregistrys` table.

### Trigger

| Property | Value |
|----------|-------|
| Type | When a row is added (Dataverse webhook) |
| Table | `fsi_provisioninglog` |
| Scope | Organization |
| Filter expression | `fsi_action eq 13 and fsi_success eq true` |
| Concurrency | Single instance |

The trigger fires when a `fsi_provisioninglog` row is created with action = 13 (`ProvisioningCompleted`) and success = true.

### Step-by-Step Build Instructions

#### Step 1 — Get ELM Request Record

Add a **Get a row by ID** action:
- Table: `fsi_environmentrequests`
- Row ID: `triggerBody()?['_fsi_environmentrequest_value']`
- Select columns: `fsi_environmentid,fsi_environmentname,fsi_environmenturl,fsi_zone,fsi_securitygroupid,fsi_requestnumber,fsi_environmenttype`
- Retry policy: Exponential, 3 retries, 10s–1min

#### Step 2 — Extract Provisioning Data

Add a **Compose** action that runs after Step 1 succeeds:
- Build a JSON object with:
  - `environmentId`: from the ELM request `fsi_environmentid`
  - `environmentName`: from `fsi_environmentname`
  - `environmentUrl`: from `fsi_environmenturl`
  - `zone`: from `fsi_zone`
  - `securityGroupId`: from `fsi_securitygroupid`
  - `requestNumber`: from `fsi_requestnumber`
  - `environmentType`: from `fsi_environmenttype`
  - `provisionedAt`: `utcNow()`

#### Step 3 — Handle Get Request Failure

Add a **Scope** that runs if Step 1 fails or times out:

1. **Add a row (Dataverse)** — Log failure to `fsi_provisioninglogs`
   - `fsi_name`: `INT-Init-FAILED-GetRequest-{utcNow('yyyyMMddHHmmss')}`
   - `fsi_environmentrequest`: Lookup bound to `/fsi_environmentrequests({trigger request value})`
   - `fsi_action`: `11` (SolutionInitialization)
   - `fsi_actiondetails`: JSON with error context and request value
   - `fsi_actor`: `CrossSolutionIntegration`
   - `fsi_actortype`: `3` (System)
   - `fsi_success`: `false`

2. **Post message in a chat or channel** — Notify Teams (runs after log succeeds, fails, or times out)
   - Message: Warning that the ELM environment request record could not be retrieved, with the request value and suggested investigation steps

#### Step 4 — Validate Required Fields

Add a **Condition** that runs after Step 2 succeeds:

- **Condition (OR):**
  - `coalesce(environmentId, '')` equals `""`
  - `coalesce(environmentName, '')` equals `""`

- **If yes:**
  1. **Add a row** — Log validation failure to `fsi_provisioninglogs` with details about which field was null/empty
  2. **Terminate** — Failed with code `NullRequiredField` and message explaining that a corrupt ACV registry entry would result

- **If no:** Continue to registration

#### Step 5 — Register in ACV

Add a **Scope** (`Register_In_ACV`) that runs after Step 4 succeeds:

1. **List rows** — Check if environment already exists in ACV
   - Table: `fsi_environmentregistrys`
   - Filter: `fsi_environmentid eq '{environmentId}'`
   - Select: `fsi_environmentregistryid`
   - Top count: `1`

2. **Condition** — Environment not registered (length = 0)

3. **If not registered → Add a row** — Create ACV registry entry
   - Table: `fsi_environmentregistrys`
   - Fields:
     - `fsi_name`: environment name
     - `fsi_environmentid`: environment ID from ELM
     - `fsi_zone`: zone from ELM request
     - `fsi_status`: `1` (Active)
     - `fsi_environmenttype`: from ELM request
     - `fsi_environmenturl`: from ELM request
     - `fsi_discoveredon`: `utcNow()`
     - `fsi_notes`: `Auto-registered via ELM provisioning. Request: {requestNumber}`

4. **If already registered → Update a row** — Update existing ACV registry entry
   - Update `fsi_zone`, set `fsi_status` = 1, update `fsi_notes` with re-provisioning context

#### Step 6 — Log Initialization Success

After the Register_In_ACV scope succeeds:

1. **Compose** — Build init details JSON with `acvRegistered: true`, zone, and environment ID

2. **Add a row (Dataverse)** — Log to `fsi_provisioninglogs`
   - `fsi_name`: `INT-Init-{environmentName}`
   - `fsi_action`: `11`
   - `fsi_actiondetails`: Stringified init details
   - `fsi_actor`: `CrossSolutionIntegration`
   - `fsi_actortype`: `3`
   - `fsi_success`: `true`

#### Step 7 — Handle ACV Registration Failure

Add a **Scope** that runs if the Register_In_ACV scope fails or times out:

1. **Compose** — Build failure details JSON with `acvRegistered: false` and error description
2. **Add a row** — Log failure to `fsi_provisioninglogs`
3. **Post message in a chat or channel** — Notify Teams with environment name, zone, failure status, and manual registration instructions

#### Step 8 — Success Notification

After Step 6 (Log Initialization) succeeds, add a **Post message in a chat or channel** action:
- Message body (HTML):
  ```html
  <p><strong>🔗 Environment Initialized for Governance</strong></p>
  <p>Environment: {environmentName}<br/>
  Zone: {zone}<br/>
  ACV Registry: ✅ Registered<br/>
  Source: ELM Request {requestNumber}</p>
  ```

Add a **Compose** fallback that runs if the Teams notification fails:
- Value: `Teams notification failed — initialization completed successfully but notification could not be sent.`

---

## Error Handling Summary

Both flows implement consistent error handling patterns:

| Pattern | Implementation |
|---------|---------------|
| **Retry policy** | Exponential backoff on all Dataverse and Teams actions: 3 retries, 10s initial, 1-min max |
| **Scope timeouts** | 10-minute timeout on each sync scope (CD-SolutionFeedCollector) |
| **Per-scope error logging** | Failed scopes write to `fsi_integrationerrorlogs` (collector) or `fsi_provisioninglogs` (initializer) |
| **Teams notification fallback** | Compose action absorbs Teams failures so they do not fail the flow |
| **Parameter validation** | Guard condition terminates flow early if required configuration is missing |
| **Null field protection** | ELM initializer validates environmentId/environmentName before ACV registration to prevent corrupt records |
| **Single instance** | Both triggers use `SingleInstance` concurrency to prevent parallel execution |

---

## Testing

### CD-SolutionFeedCollector

1. **Prerequisite:** Populate all 7 `fsi_INT_ControlGuid_*` environment variables with valid control master GUIDs from `fsi_controlmasters`
2. **Prerequisite:** Confirm at least one Tier 2 solution has recent validation history records
3. **Test run:** Manually trigger the flow from Power Automate designer
4. **Verify:** Check `fsi_controlassessments` for new/updated records with today's date
5. **Verify:** Check the Teams channel for the summary notification
6. **Error test:** Temporarily blank one control GUID parameter → flow should terminate with `MissingConfiguration`
7. **Error test:** Disable Dataverse connection → verify error logged to `fsi_integrationerrorlogs`

### ELM-SolutionInitializer

1. **Prerequisite:** ELM solution deployed with `fsi_provisioninglogs` and `fsi_environmentrequests` tables
2. **Prerequisite:** ACV `fsi_environmentregistrys` table exists
3. **Test trigger:** Create a `fsi_provisioninglog` row with `fsi_action = 13` and `fsi_success = true` referencing a valid environment request
4. **Verify:** Check `fsi_environmentregistrys` for the new environment entry
5. **Verify:** Check `fsi_provisioninglogs` for the `INT-Init-*` success entry
6. **Verify:** Check Teams channel for initialization notification
7. **Re-provision test:** Trigger again with the same environment → should update (not duplicate) the ACV registry entry
8. **Error test:** Trigger with an invalid `_fsi_environmentrequest_value` → should log failure and send Teams alert

---

## Related Resources

- [README — Solution Overview](../README.md)
- [SCHEMA_CONTRACT.md](SCHEMA_CONTRACT.md) — Cross-solution data contract and option set values
- [STATUS_MAPPING.md](STATUS_MAPPING.md) — Per-solution status translation logic
- [CONFIGURATION.md](CONFIGURATION.md) — Setup and configuration guide
- [ELM_INTEGRATION.md](ELM_INTEGRATION.md) — ELM provisioning hook integration details
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — Common issues and resolution
