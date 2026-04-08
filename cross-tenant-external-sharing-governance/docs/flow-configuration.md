# Flow Configuration Guide

> **Documentation-only** — These instructions describe how to manually build each flow in Power Automate designer. This solution does not include exported flow JSON files.

## Overview

This guide provides step-by-step instructions for building the six Cross-Tenant External Sharing Governance (CTSG) Power Automate flows. Together, these flows validate tenant isolation settings, detect unauthorized external agent shares, audit Entra cross-tenant access policies, manage external tenant onboarding with dual-approval, remediate unauthorized access, and drive annual review cycles.

**Flows to Build:**

1. Validate-TenantIsolation-Daily (Scheduled Cloud Flow)
2. Detect-ExternalAgentShares-Daily (Scheduled Cloud Flow)
3. Audit-EntraCrossTenantSettings-Weekly (Scheduled Cloud Flow)
4. Execute-ExternalTenantOnboarding (Instant Cloud Flow)
5. Remediate-UnauthorizedExternalAccess (Instant Cloud Flow)
6. Send-AnnualReviewReminders-Daily (Scheduled Cloud Flow)

## ⚠️ Option Set Value Reference

All choice/option-set fields in OData expressions use **integer values**, not string labels. The schema source of truth is `scripts/create_ctsg_dataverse_schema.py`. This solution uses **0-based** option set values. Key mappings:

| Option Set | Values |
|-----------|--------|
| `fsi_ctsg_approvalstatus` | 0=Pending, 1=Approved, 2=Expired, 3=Suspended, 4=Revoked |
| `fsi_ctsg_findingstatus` | 0=Open, 1=Under Review, 2=Remediated, 3=Approved Exception, 4=False Positive |
| `fsi_ctsg_severity` | 0=Critical, 1=High, 2=Medium, 3=Low |
| `fsi_ctsg_findingtype` | 0=Unapproved Tenant Isolation Exception, 1=Unapproved Guest Share, 2=Unapproved B2B Access, 3=Tenant Isolation Disabled, 4=Approved Tenant - Review Required |
| `fsi_ctsg_governancelayer` | 0=Layer 1 (Tenant Isolation), 1=Layer 2 (Entra CTA), 2=Layer 3 (Agent Share) |
| `fsi_ctsg_remediationstatus` | 0=Pending, 1=Approved for Auto-Remediation, 2=Manually Remediated, 3=Deferred |
| `fsi_ctsg_eventtype` | 0–16 (see `create_ctsg_dataverse_schema.py` for full mapping) |
| `fsi_acv_zone` | 0=Unclassified, 1=Zone 1, 2=Zone 2, 3=Zone 3 |

## Prerequisites

- All Dataverse tables deployed via `create_ctsg_dataverse_schema.py`
- All environment variables configured via `create_ctsg_environment_variables.py`
- All connection references created via `create_ctsg_connection_references.py`
- Two Managed Identities provisioned (see [Prerequisites](prerequisites.md))
- `agent-registry-automation` solution deployed (provides `fsi_agentinventory.fsi_zone`)
- `unrestricted-agent-sharing-detector` solution deployed

## Connections Required

| Connector | Purpose | License |
|-----------|---------|---------|
| **Dataverse** | Read/write governance tables | Included |
| **HTTP with Microsoft Entra ID** | Power Platform Admin API, Graph API, Entra CTA API calls | Premium |
| **Microsoft Teams** | Notifications, Adaptive Cards, daily summaries | Included |
| **Approvals** | Remediation approval, dual-approval tenant onboarding | Included |
| **Office 365 Outlook** | Fallback email notifications | Included |

## Managed Identities

| Identity | Used By | Permissions |
|----------|---------|-------------|
| `MI-CrossTenantReadOnly` | Flows 1, 2, 3, 6 | Read-only access to PPAC API, Graph API, Entra CTA policies |
| `MI-CrossTenantReadWrite` | Flows 4, 5 | Read/write access to PPAC tenant isolation, Entra CTA policies, Graph role assignments |

---

## Feature Flag

> **CRITICAL:** Every flow must check the `IsCrossTenantGovernanceEnabled` environment variable as its **first action**. If the value is `"false"`, the flow must log a skip event to `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Feature Flag Skip"` and terminate with `Cancelled` status and message `"Cross-Tenant Governance not enabled"`. This gate prevents API calls before the solution is fully configured.

---

## Flow 1: Validate-TenantIsolation-Daily

**Type:** Scheduled Cloud Flow
**Trigger:** Recurrence — Daily at 04:00 AM UTC
**Identity:** `MI-CrossTenantReadOnly`
**Purpose:** Validate Power Platform tenant isolation is enabled and all allow-list entries are approved

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Scheduled Cloud Flow
   - Flow name: `Validate-TenantIsolation-Daily`
   - Recurrence: Daily at 04:00 UTC

2. **Check Feature Flag**
   - Action: Environment Variable — Get value
   - Variable: `IsCrossTenantGovernanceEnabled`
   - **Condition:** Value equals `"false"`
   - **If true:**
     1. Create record in `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Feature Flag Skip"`
     2. Terminate with status `Cancelled`, message `"Cross-Tenant Governance not enabled"`
   - **If false:** Continue to Step 3

3. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `runId`: Expression `guid()`
   - `findingsCount`: Integer `0`
   - `tenantIsolationEnabled`: Boolean `false`

4. **Validate API 1 Schema — Tenant Settings**
   - Action: HTTP with Microsoft Entra ID

   | Parameter | Value |
   |-----------|-------|
   | Method | `GET` |
   | Base Resource URL | `https://api.powerplatform.com` |
   | Microsoft Entra ID Resource URI | `https://api.powerplatform.com` |
   | URI | `/governance/tenantSettings?api-version=2022-03-01-preview` |

   - **Condition:** Response body contains `tenantIsolationEnabled` property
   - **If false (schema validation failed):**
     1. Send Teams alert to `FlowAdministrators` channel: `"API Schema Validation Failed — tenantSettings endpoint does not contain tenantIsolationEnabled property. API may have changed."`
     2. Create `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"API Schema Validation Failed"`, `fsi_eventdetails` = full response body
     3. Terminate with status `Failed`
   - **If true:** Continue

   **Retry Policy:**
   ```json
   {
     "type": "exponential",
     "count": 3,
     "interval": "PT30S",
     "minimumInterval": "PT10S",
     "maximumInterval": "PT5M"
   }
   ```

5. **Validate API 2 Schema — Cross-Tenant Policies**
   - Action: HTTP with Microsoft Entra ID

   | Parameter | Value |
   |-----------|-------|
   | Method | `GET` |
   | Base Resource URL | `https://api.powerplatform.com` |
   | Microsoft Entra ID Resource URI | `https://api.powerplatform.com` |
   | URI | `/governance/crossTenantPolicies?api-version=2022-03-01-preview` |

   - **Condition:** Response body `value` array exists and entries contain `tenantId` and `direction` fields
   - **If false:** Same schema-failure handling as Step 4

6. **Check Tenant Isolation Status**
   - **Condition:** `tenantIsolationEnabled` equals `false`
   - **If true (isolation disabled):**
     1. Set `findingsCount` = `findingsCount + 1`
     2. Create `fsi_externalsharefinding` record:
        - `fsi_findingtype`: `"Tenant Isolation Disabled"` (Critical)
        - `fsi_severity`: `0` (Critical)
        - `fsi_findingstatus`: `0` (Open)
        - `fsi_detecteddate`: Variable `timestamp`
        - `fsi_remediationnotes`: `"Power Platform tenant isolation is disabled. All external tenants can access resources without restriction."`
     3. Trigger Flow 5 (`Remediate-UnauthorizedExternalAccess`) with finding ID
   - **If false:** Continue

7. **Get Approved Tenants**
   - Action: "List rows" (Dataverse)
   - Table: `fsi_approvedexternaltenants`
   - Filter: `fsi_approvalstatus eq 1`
   - Select: `fsi_tenantid,fsi_tenantname,fsi_primarydomain,fsi_ppisolationdirection,fsi_approvalstatus`

8. **Build Approved Tenant Index**
   - Action: Select — build a lookup array of approved tenant IDs for quick comparison
   - Map `fsi_tenantid` → full record (including `fsi_ppisolationdirection`)

9. **For Each Allow-List Entry**
   - Action: Apply to each on cross-tenant policy entries from Step 5
   - **Concurrency:** Set degree of parallelism to `1` (sequential to avoid throttling)

   9a. **Check Against Approved Registry**
   - **Condition:** Current entry `tenantId` exists in approved tenant index
   - **If false (unapproved entry):**
     1. Increment `findingsCount`
     2. Create `fsi_externalsharefinding`:
        - `fsi_findingtype`: `"Unapproved Tenant Isolation Exception"`
        - `fsi_severity`: `1` (High)
        - `fsi_findingstatus`: `0` (Open)
        - `fsi_externaltenanttenantid`: Entry `tenantId`
        - `fsi_remediationnotes`: Expression `concat('Tenant ', tenantId, ' found in PPAC allow-list but not in approved registry')`

   9b. **Check Direction Match**
   - **Condition:** Entry `direction` matches approved record `fsi_ppisolationdirection`
   - **If false (direction mismatch):**
     1. Increment `findingsCount`
     2. Create `fsi_externalsharefinding`:
        - `fsi_findingtype`: `"Unapproved Tenant Isolation Exception"`
        - `fsi_severity`: `2` (Medium)
        - `fsi_findingstatus`: `0` (Open)
        - `fsi_remediationnotes`: Expression `concat('Approved direction: ', approvedDirection, '; Actual direction: ', actualDirection)`

10. **Create Tenant Isolation Record**
    - Action: "Create a new record" (Dataverse)
    - Table: `fsi_tenantisolationrecord`
    - Fields:
      - `fsi_name`: Expression `concat('TI-Snapshot-', variables('runId'))`
      - `fsi_isolationenabled`: Variable `tenantIsolationEnabled`
      - `fsi_allowlistcount`: Length of cross-tenant policy entries
      - `fsi_findingscreated`: Variable `findingsCount`
      - `fsi_allowlistsnapshot`: Full response body from Steps 4 and 5 serialized
      - `fsi_auditdate`: Variable `timestamp`

11. **Log Compliance Event**
    - **Condition:** `findingsCount` equals `0`
    - **If true:**
      - Create `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Tenant Isolation Validated"`, `fsi_eventdetails` = `"All allow-list entries match approved tenant registry"`
    - **If false:**
      - Create `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Tenant Isolation Violation"`, `fsi_eventdetails` = Expression `concat(variables('findingsCount'), ' finding(s) detected')`

### Error Handling

Wrap Steps 4–11 in a **Scope: Main Logic** action. Add a parallel **Scope: Catch** configured with **Run after** → Failed, Timed out, Cancelled:

1. Log error to `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Flow Error"`, `fsi_eventdetails` = error message
2. Send Teams alert to `FlowAdministrators` with flow name, run ID, and error details
3. Terminate with status `Failed`

---

## Flow 2: Detect-ExternalAgentShares-Daily

**Type:** Scheduled Cloud Flow
**Trigger:** Recurrence — Daily at 05:00 AM UTC
**Identity:** `MI-CrossTenantReadOnly`
**Purpose:** Detect guest users with agent role assignments and create findings for unapproved external shares

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Scheduled Cloud Flow
   - Flow name: `Detect-ExternalAgentShares-Daily`
   - Recurrence: Daily at 05:00 UTC

2. **Check Feature Flag**
   - Same pattern as Flow 1, Step 2

3. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `runId`: Expression `guid()`
   - `findingsCount`: Integer `0`
   - `guestsProcessed`: Integer `0`
   - `internalDomains`: Array (empty — populated in Step 4)
   - `guestUserIndex`: Object (empty — populated in Step 5)

4. **Get Home Tenant Verified Domains**
   - Action: HTTP with Microsoft Entra ID

   | Parameter | Value |
   |-----------|-------|
   | Method | `GET` |
   | Base Resource URL | `https://graph.microsoft.com` |
   | Microsoft Entra ID Resource URI | `https://graph.microsoft.com` |
   | URI | `/v1.0/organization?$select=id,displayName,verifiedDomains` |

   - Parse response to build `internalDomains` array from `verifiedDomains[].name`

5. **Get All Guest Users**
   - Action: HTTP with Microsoft Entra ID

   | Parameter | Value |
   |-----------|-------|
   | Method | `GET` |
   | Base Resource URL | `https://graph.microsoft.com` |
   | Microsoft Entra ID Resource URI | `https://graph.microsoft.com` |
   | URI | `/v1.0/users?$filter=userType eq 'Guest'&$select=id,displayName,mail,userPrincipalName,externalUserState,createdDateTime,creationType&$count=true` |

   **Headers:**
   ```json
   {
     "ConsistencyLevel": "eventual"
   }
   ```

   > **Pagination:** The Graph API returns a maximum of 100 users per page. If `@odata.nextLink` is present in the response, loop with subsequent GET requests until all pages are retrieved.

   **Retry Policy:**
   ```json
   {
     "type": "exponential",
     "count": 3,
     "interval": "PT30S",
     "minimumInterval": "PT10S",
     "maximumInterval": "PT5M"
   }
   ```

6. **For Each Guest User — Determine Home Tenant Domain**

   For each guest user, apply the **5-value detection method** using a three-method fallback chain to resolve the guest's home tenant domain.

   #### Method 1: EXT# UPN Parsing

   - **Condition:** `userPrincipalName` contains `#EXT#`
   - **If true:**
     1. Use the **rightmost** occurrence of `#EXT#` in the UPN
     2. Parse the substring before `#EXT#` to extract the original UPN
     3. Extract the domain from the original UPN (substring after the last underscore before `@`)
     4. **Edge cases:**
        - Multiple underscores in original UPN → take the last underscore as the domain separator
        - MSA guests (`live.com`, `outlook.com`, `hotmail.com`) → set `method1Domain` to the extracted domain and flag `"MSA origin"` in `fsi_remediationnotes`
        - UPN contains `#EXT#` more than once → always use the rightmost occurrence
     5. If domain extracted successfully: `method1Domain` = extracted domain
     6. If extraction fails: `method1Domain` = `null`
   - **If false:** `method1Domain` = `null`

   #### Method 2: Mail Field

   - **Condition:** `mail` field is not null and not empty
   - **If true:**
     1. `method2Domain` = domain portion of `mail` field (substring after `@`)
     2. **Condition:** `method2Domain` is in `internalDomains` array
        - **If true:** Discard — this is an internal user, not external. Skip to next guest.
        - **If false:** `method2Domain` is a candidate external domain
   - **If false:** `method2Domain` = `null`

   #### Method 3: CreationType Confirmation

   - **Condition:** `creationType` equals `"Invitation"`
   - **If true:** `externalOriginConfirmed` = `true`
   - **If false:** `externalOriginConfirmed` = `false`
   - **Note:** Method 3 confirms external B2B origin but does not independently resolve a domain.

   #### Determine `homeTenantDomain` and `fsi_guestdetectionmethod`

   Use the following decision table to set the final values:

   | Condition | `homeTenantDomain` | `fsi_guestdetectionmethod` | Notes |
   |-----------|-------------------|---------------------------|-------|
   | `method1Domain` AND `method2Domain` both not null AND equal | `method1Domain` | `"Multi-Method Agreed"` | Highest confidence |
   | `method1Domain` not null AND `method2Domain` null | `method1Domain` | `"EXT# Parsing"` | — |
   | `method1Domain` null AND `method2Domain` not null | `method2Domain` | `"Mail Field"` | — |
   | `method1Domain` AND `method2Domain` both not null AND NOT equal | `method2Domain` | `"Mail Field"` | Append mismatch note to `fsi_remediationnotes`: `concat('UPN domain mismatch: EXT#=', method1Domain, ' vs Mail=', method2Domain)` |
   | Both null AND `externalOriginConfirmed` = `true` | `"Unknown"` | `"CreationType"` | Append note: `"B2B origin confirmed via creationType=Invitation but domain could not be resolved"` |
   | All methods failed | `"Unknown"` | `"Unresolved"` | Append note with all raw field values for manual review; assign conservative High severity |

   - Build `guestUserIndex` mapping `id` → `{ displayName, homeTenantDomain, detectionMethod, remediationNotes }`

7. **Get Approved Tenants**
   - Action: "List rows" (Dataverse)
   - Table: `fsi_approvedexternaltenants`
   - Filter: `fsi_approvalstatus eq 1`
   - Build `approvedTenantIndex` keyed by both `fsi_primarydomain` and `fsi_tenantid`

8. **Get All Power Platform Environments**
   - Action: HTTP with Microsoft Entra ID

   | Parameter | Value |
   |-----------|-------|
   | Method | `GET` |
   | Base Resource URL | `https://api.powerplatform.com` |
   | Microsoft Entra ID Resource URI | `https://api.powerplatform.com` |
   | URI | `/appmanagement/environments?api-version=2022-03-01-preview` |

9. **For Each Environment**
   - Action: Apply to each on environments from Step 8
   - **Concurrency:** Set degree of parallelism to `5`

   9a. **Get Agents in Environment**
   - Retrieve agent list from the environment's Copilot Studio inventory

   9b. **For Each Agent**
   - Action: Apply to each on agents

   9b-i. **Get Agent Role Assignments**
   - Action: HTTP with Microsoft Entra ID
   - Retrieve role assignments for the current agent
   - **Schema validation:** Confirm response contains expected `principalId` field before processing

   9b-ii. **For Each Role Assignment**

   - **Condition:** `principalId` exists in `guestUserIndex`
   - **If true (guest found):**

     1. **Check Approved Status**
        - Look up `homeTenantDomain` from `guestUserIndex`
        - **Condition:** `homeTenantDomain` exists in `approvedTenantIndex`
        - **If true:** Skip — approved external share
        - **If false:** Continue to create finding

     2. **Deduplication Check**
        - Query `fsi_externalsharefindings` for existing Open finding matching same `fsi_agentid`, `fsi_externaltenantname`, and `fsi_findingtype`:
          ```
          fsi_externalsharefindings?$filter=fsi_agentid eq '{agentId}' and fsi_externaltenantname eq '{homeTenantDomain}' and fsi_findingtype eq 1 and fsi_findingstatus eq 0&$top=1
          ```
        - If match exists: Update `fsi_detecteddate` to current timestamp, skip creation

     3. **Determine Severity from Agent Zone**
        - Query `fsi_agentinventory` for agent's `fsi_zone` value:
          ```
          fsi_agentinventorys?$filter=fsi_agentid eq '{agentId}'&$select=fsi_zone&$top=1
          ```
        - Apply severity mapping:

          | `fsi_zone` Value | Severity | Code |
          |------------------|----------|------|
          | `3` (Zone 3) | Critical | `0` |
          | `2` (Zone 2) | High | `1` |
          | `1` (Zone 1) | Medium | `2` |
          | `null` or not found | High (conservative) | `1` |

     4. **Create Finding**
        - Action: "Create a new record" (Dataverse)
        - Table: `fsi_externalsharefinding`
        - Fields:
          - `fsi_findingtype`: `"Unapproved Guest Share"`
          - `fsi_severity`: Severity code from zone mapping
          - `fsi_findingstatus`: `0` (Open)
          - `fsi_agentid`: Agent GUID
          - `fsi_agentname`: Agent display name
          - `fsi_environmentid`: Environment GUID
          - `fsi_externaltenantname`: `homeTenantDomain` from guest index
          - `fsi_externaluserupn`: Guest `userPrincipalName`
          - `fsi_guestdetectionmethod`: Detection method string from Step 6
          - `fsi_detecteddate`: Variable `timestamp`
          - `fsi_remediationnotes`: Any accumulated notes from detection
        - Increment `findingsCount`

     5. **Trigger Flow 5** with finding ID

10. **Resolve External Tenant Names**
    - For each unique `homeTenantDomain` in findings, attempt tenant name resolution:
    - Action: HTTP with Microsoft Entra ID

    | Parameter | Value |
    |-----------|-------|
    | Method | `GET` |
    | Base Resource URL | `https://graph.microsoft.com` |
    | Microsoft Entra ID Resource URI | `https://graph.microsoft.com` |
    | URI | `/v1.0/tenantRelationships/findTenantInformationByDomainName(domainName='{domain}')` |

    - If resolution succeeds: Update finding records with resolved tenant name
    - If resolution fails: Do not block — log warning and continue

11. **Send Daily Summary**
    - Action: Microsoft Teams → Post Adaptive Card in a chat or channel
    - Channel: Environment variable `GovernanceTeamChannelId`
    - Card: Daily scan summary Adaptive Card (see [Teams Adaptive Card Templates](#teams-adaptive-card-templates) — Template 1)

### Error Handling

Wrap Steps 4–11 in a **Scope: Main Logic**. Add parallel **Scope: Catch** with **Run after** → Failed, Timed out, Cancelled:

1. Log error to `fsi_crosstenantcomplianceevent`
2. Send Teams alert with flow name, run ID, error details
3. Terminate with status `Failed`

---

## Flow 3: Audit-EntraCrossTenantSettings-Weekly

**Type:** Scheduled Cloud Flow
**Trigger:** Recurrence — Every Monday at 06:00 AM UTC
**Identity:** `MI-CrossTenantReadOnly`
**Purpose:** Audit Entra ID cross-tenant access (CTA) settings against governance baseline and approved tenant registry

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Scheduled Cloud Flow
   - Flow name: `Audit-EntraCrossTenantSettings-Weekly`
   - Recurrence: Week, Monday at 06:00 UTC

2. **Check Feature Flag**
   - Same pattern as Flow 1, Step 2

3. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `runId`: Expression `guid()`
   - `findingsCount`: Integer `0`
   - `baselineInboundBlocked`: Environment variable `CTABaseline_InboundB2BBlocked`
   - `baselineOutboundBlocked`: Environment variable `CTABaseline_OutboundB2BBlocked`
   - `baselineDirectConnectBlocked`: Environment variable `CTABaseline_DirectConnectBlocked`

4. **Get Default CTA Policy**
   - Action: HTTP with Microsoft Entra ID

   | Parameter | Value |
   |-----------|-------|
   | Method | `GET` |
   | Base Resource URL | `https://graph.microsoft.com` |
   | Microsoft Entra ID Resource URI | `https://graph.microsoft.com` |
   | URI | `/v1.0/policies/crossTenantAccessPolicy/default` |

   - Parse response to capture:
     - `b2bCollaborationInbound` settings
     - `b2bCollaborationOutbound` settings
     - `b2bDirectConnectInbound` settings
     - `b2bDirectConnectOutbound` settings

   **Retry Policy:**
   ```json
   {
     "type": "exponential",
     "count": 3,
     "interval": "PT30S",
     "minimumInterval": "PT10S",
     "maximumInterval": "PT5M"
   }
   ```

5. **Evaluate Default Policy Against Baseline**

   5a. **Check Inbound B2B**
   - **Condition:** Default inbound B2B `isBlocked` does NOT match `baselineInboundBlocked`
   - **If true:**
     1. Increment `findingsCount`
     2. Create `fsi_externalsharefinding`:
        - `fsi_findingtype`: `"Unapproved B2B Access"`
        - `fsi_severity`: `2` (Medium)
        - `fsi_findingstatus`: `0` (Open)
        - `fsi_remediationnotes`: Expression `concat('Expected inbound B2B blocked=', baselineInboundBlocked, '; Actual=', actualValue)`

   5b. **Check Outbound B2B**
   - Same pattern — compare against `baselineOutboundBlocked`
   - Finding type: `"Unapproved B2B Access"`

   5c. **Check Direct Connect**
   - Same pattern — compare against `baselineDirectConnectBlocked`
   - Finding type: `"Unapproved B2B Access"`

6. **Get All Partner CTA Policies**
   - Action: HTTP with Microsoft Entra ID

   | Parameter | Value |
   |-----------|-------|
   | Method | `GET` |
   | Base Resource URL | `https://graph.microsoft.com` |
   | Microsoft Entra ID Resource URI | `https://graph.microsoft.com` |
   | URI | `/v1.0/policies/crossTenantAccessPolicy/partners` |

   > **Pagination:** Follow `@odata.nextLink` if present.

7. **Get Approved Tenants**
   - Action: "List rows" (Dataverse)
   - Table: `fsi_approvedexternaltenants`
   - Filter: `fsi_approvalstatus eq 1`

8. **For Each Partner Policy Entry**
   - Action: Apply to each on partner policies from Step 6

   8a. **Check Against Approved Registry**
   - **Condition:** Partner `tenantId` exists in approved tenant index
   - **If false (unapproved partner):**
     1. Increment `findingsCount`
     2. Create `fsi_externalsharefinding`:
        - `fsi_findingtype`: `"Unapproved B2B Access"`
        - `fsi_severity`: `2` (Medium)
        - `fsi_findingstatus`: `0` (Open)
        - `fsi_externaltenanttenantid`: Partner `tenantId`
        - `fsi_remediationnotes`: `"Partner CTA policy exists for tenant not in approved registry"`

   8b. **Check Scope Against Approval**
   - **Condition:** Partner entry exists in approved registry but scope exceeds approved level (e.g., approved for inbound-only but outbound also enabled)
   - **If true:**
     1. Increment `findingsCount`
     2. Create `fsi_externalsharefinding`:
        - `fsi_findingtype`: `"Unapproved B2B Access"`
        - `fsi_severity`: `2` (Medium)
        - `fsi_findingstatus`: `0` (Open)
        - `fsi_remediationnotes`: Expression detailing approved vs. actual scope

9. **Create Entra CTA Record**
   - Action: "Create a new record" (Dataverse)
   - Table: `fsi_entractarecord`
   - Fields:
     - `fsi_name`: Expression `concat('CTA-Audit-', variables('runId'))`
     - `fsi_partnersnapshot`: Serialized default policy response from Step 4
     - `fsi_partnerentrycount`: Count of partner policies from Step 6
     - `fsi_findingscreated`: Variable `findingsCount`
     - `fsi_auditdate`: Variable `timestamp`

10. **Log Compliance Event**
    - Create `fsi_crosstenantcomplianceevent`:
      - `fsi_eventtype`: If `findingsCount` = 0 → `"Entra CTA Audited"` else `"Entra CTA Violation"`
      - `fsi_eventdetails`: Expression `concat('Partner policies audited: ', partnerCount, '; Findings: ', findingsCount)`

### Error Handling

Same scope-based try/catch pattern as Flow 1.

---

## Flow 4: Execute-ExternalTenantOnboarding

**Type:** Instant Cloud Flow
**Trigger:** Instant — from External Tenant Registry Portal (manual trigger or HTTP request)
**Identity:** `MI-CrossTenantReadWrite`
**Purpose:** Process external tenant onboarding requests with dual-approval workflow and automatic expiration

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Instant Cloud Flow
   - Flow name: `Execute-ExternalTenantOnboarding`
   - Trigger: Manually trigger a flow (or HTTP request trigger from portal)

2. **Check Feature Flag**
   - Same pattern as Flow 1, Step 2

3. **Receive Input Parameters**
   - Parse trigger inputs:
     - `requestedTenantId`: String (GUID)
     - `requestedTenantDomain`: String
     - `businessJustification`: String
     - `requestedDirection`: Choice (Inbound / Outbound / Both)
     - `requestorUpn`: String (email)
     - `requestorTeam`: String

4. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `requestId`: Expression `guid()`
   - `annualReviewDate`: Expression `addMonths(utcNow(), 12)`
   - `securityTeamUpn`: Environment variable `SecurityTeamUPN`
   - `governanceCommitteeUpn`: Environment variable `GovernanceCommitteeUPN`

5. **Input Validation**

   5a. **Validate Business Justification Length**
   - **Condition:** Length of `businessJustification` is less than 100 characters
   - **If true:**
     1. Send notification to requestor: `"Business justification must be at least 100 characters. Please resubmit with a detailed explanation."`
     2. Terminate with status `Cancelled`

   5b. **Check for Duplicate Request**
   - Query `fsi_approvedexternaltenants`:
     ```
     fsi_approvedexternaltenants?$filter=fsi_tenantid eq '{requestedTenantId}' and fsi_approvalstatus eq 1&$top=1
     ```
   - **Condition:** Record exists (tenant already approved)
   - **If true:**
     1. Send notification to requestor: `"Tenant is already approved. No new request is required."`
     2. Terminate with status `Cancelled`

6. **Resolve Tenant Information**
   - Action: HTTP with Microsoft Entra ID

   | Parameter | Value |
   |-----------|-------|
   | Method | `GET` |
   | Base Resource URL | `https://graph.microsoft.com` |
   | Microsoft Entra ID Resource URI | `https://graph.microsoft.com` |
   | URI | `/v1.0/tenantRelationships/findTenantInformationByDomainName(domainName='{requestedTenantDomain}')` |

   - Capture resolved `tenantId` and `displayName`
   - **Condition:** Resolved `tenantId` does NOT match `requestedTenantId`
   - **If true:** Append mismatch note to approval cards: `concat('WARNING: Requested tenant ID (', requestedTenantId, ') does not match resolved tenant ID (', resolvedTenantId, '). Verify before approving.')`

7. **Create Pending Approval Record**
   - Action: "Create a new record" (Dataverse)
   - Table: `fsi_approvedexternaltenant`
   - Fields:
     - `fsi_name`: Expression `concat('Onboard-', variables('requestId'))`
     - `fsi_tenantid`: `requestedTenantId`
     - `fsi_tenantname`: Resolved `displayName` (or `requestedTenantDomain` if resolution failed)
     - `fsi_primarydomain`: `requestedTenantDomain`
     - `fsi_ppisolationdirection`: `requestedDirection`
     - `fsi_approvalstatus`: `0` (Pending)
     - `fsi_businessjustification`: `businessJustification`
     - `fsi_notes`: `requestorUpn` (include requestor UPN with prefix "Requestor: ")
     - `fsi_requestingteam`: `requestorTeam`
     - `fsi_annualreviewdue`: Variable `annualReviewDate`

8. **Log Compliance Event**
   - Create `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Tenant Onboarding Initiated"`, `fsi_eventdetails` = Expression `concat('Tenant: ', requestedTenantDomain, ' requested by ', requestorUpn)`

9. **Send Parallel Approval Requests**

   Use a **Parallel Branch** with two simultaneous approval actions:

   **Branch A — Security Team Approval:**
   - Action: Approvals → Start and wait for an approval
   - Approval type: Approve/Reject — First to respond
   - Title: Expression `concat('External Tenant Onboarding — Security Review: ', requestedTenantDomain)`
   - Assigned to: Variable `securityTeamUpn`
   - Details: Security attestation Adaptive Card (see [Template 4](#template-4-tenant-onboarding-security-attestation))
   - **Timeout:** `P10D` (10 business days)

   **Branch B — Governance Committee Approval:**
   - Action: Approvals → Start and wait for an approval
   - Approval type: Approve/Reject — First to respond
   - Title: Expression `concat('External Tenant Onboarding — Governance Review: ', requestedTenantDomain)`
   - Assigned to: Variable `governanceCommitteeUpn`
   - Details: Governance approval Adaptive Card (see [Template 5](#template-5-tenant-onboarding-governance-approval))
   - **Timeout:** `P10D` (10 business days)

10. **Handle Timeout (Either Branch)**
    - Configure **Run after** → Has timed out on both approval branches
    - **If timed out:**
      1. Update `fsi_approvedexternaltenant`:
         - `fsi_approvalstatus`: `2` (Expired)
         - `fsi_expirynotes`: `"Approval request expired after 10 business days without response from all required approvers"`
      2. Log `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Tenant Expired"`
      3. Send Teams notification to requestor, security team, and governance committee: `"External tenant onboarding request has expired due to incomplete approvals"`
      4. Terminate with status `Cancelled`

11. **Evaluate Approval Outcomes**

    **Condition:** Both Branch A AND Branch B outcomes equal `"Approve"`

    **If both approved:**
    1. Update `fsi_approvedexternaltenant`:
       - `fsi_approvalstatus`: `1` (Approved)
       - `fsi_approvaldate`: Expression `utcNow()`
       - `fsi_approvedby`: Expression `concat(securityApprover, '; ', governanceApprover)`
    2. Update PPAC tenant isolation allow-list (if applicable):
       - Action: HTTP with Microsoft Entra ID — PATCH to add tenant to allow-list
    3. Update Entra CTA partner policy (if applicable):
       - Action: HTTP with Microsoft Entra ID — create or update partner CTA policy
    4. Close any open findings for this tenant:
       - Query `fsi_externalsharefindings` where `fsi_externaltenanttenantid eq '{tenantId}' and fsi_findingstatus eq 0`
       - Update each to `fsi_findingstatus` = `2` (Remediated), `fsi_assignedto` = `"Onboarding Approval"`, `fsi_remediationdate` = `utcNow()`
    5. Log `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Tenant Approved"`
    6. Send Teams notification to requestor: `"External tenant onboarding approved"`

    **If either rejected:**
    1. Update `fsi_approvedexternaltenant`:
       - `fsi_approvalstatus`: `4` (Revoked)
       - `fsi_expirynotes`: Rejection comments from the rejecting approver
    2. Log `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Tenant Revoked"`
    3. Send Teams notification to requestor with rejection reason

### Error Handling

Same scope-based try/catch pattern. For approval actions specifically, configure **Run after** for both **Has failed** and **Has timed out** branches.

---

## Flow 5: Remediate-UnauthorizedExternalAccess

**Type:** Instant Cloud Flow
**Trigger:** Instant — called from Flow 1, Flow 2, or Registry Portal
**Identity:** `MI-CrossTenantReadWrite`
**Purpose:** Remediate unauthorized external access findings through approval-gated actions across three layers

### Remediation Layers

| Layer | Scope | Action |
|-------|-------|--------|
| Layer 3 | Individual role assignment | Remove guest user's agent role assignment |
| Layer 2 | Entra CTA partner policy | Restrict or remove partner CTA configuration |
| Layer 1 | PPAC tenant isolation | Remove tenant from allow-list (or defer for manual action) |

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Instant Cloud Flow
   - Flow name: `Remediate-UnauthorizedExternalAccess`
   - Trigger: Manually trigger a flow (accepts `findingId` parameter)

2. **Check Feature Flag**
   - Same pattern as Flow 1, Step 2

3. **Retrieve Finding Record**
   - Action: "Get a row by ID" (Dataverse)
   - Table: `fsi_externalsharefinding`
   - Row ID: Trigger input `findingId`

4. **Check for Duplicate Processing**
   - **Condition:** `fsi_findingstatus` is NOT `0` (Open)
   - **If true (already handled):**
     1. Log `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Duplicate Remediation Skipped"`, `fsi_eventdetails` = Expression `concat('Finding ', findingId, ' already in status ', currentStatus)`
     2. Terminate with status `Cancelled`

5. **Set Status to Under Review**
   - Action: "Update a record" (Dataverse)
   - Table: `fsi_externalsharefinding`
   - Fields:
     - `fsi_findingstatus`: `1` (Under Review)

6. **Check Finding Type — Tenant Isolation Disabled**
   - **Condition:** `fsi_findingtype` equals `"Tenant Isolation Disabled"`
   - **If true (cannot auto-remediate):**
     1. Update finding:
        - `fsi_remediationstatus`: `3` (Deferred)
        - `fsi_remediationnotes`: `"Tenant isolation cannot be enabled via automation. Manual action required in Power Platform Admin Center → Tenant Settings → Tenant Isolation → Enable."`
     2. Send **CRITICAL** Teams alert to `FlowAdministrators` and `SecurityTeamUPN`:
        - Use Adaptive Card with red banner: `"CRITICAL: Power Platform tenant isolation is DISABLED"`
        - Include manual remediation steps in card body
     3. Log `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Critical Finding — Manual Remediation Required"`
     4. Terminate with status `Succeeded` (finding remains Open with Deferred remediation)

7. **Send Remediation Approval Request**
   - Action: Approvals → Start and wait for an approval
   - Approval type: Approve/Reject — First to respond
   - Title: Expression `concat('Remediation Approval: ', fsi_findingtype, ' — ', fsi_externaltenantname)`
   - Assigned to: Environment variable `SecurityTeamUPN`
   - Details: Remediation approval Adaptive Card (see [Template 2](#template-2-remediation-approval-request))
   - **Timeout:** `P3D` (3 days)

8. **Handle Approval Response**

   **If Approved:**

   8a. **Layer 3 — Remove Role Assignment**
   - **Condition:** Finding has associated `fsi_agentid` and `fsi_externaluserupn`
   - **If true:**
     - Action: HTTP with Microsoft Entra ID

     | Parameter | Value |
     |-----------|-------|
     | Method | `DELETE` |
     | Base Resource URL | Target environment API |
     | URI | Role assignment deletion endpoint for the specific agent and principal |

     - If DELETE succeeds: Append to `fsi_remediationnotes`: `"Layer 3: Role assignment removed"`
     - If DELETE fails: Log error, continue to Layer 2

   8b. **Layer 2 — Restrict CTA Partner Policy**
   - **Condition:** Finding involves an unapproved CTA partner
   - **If true:**
     - Action: HTTP with Microsoft Entra ID

     | Parameter | Value |
     |-----------|-------|
     | Method | `PATCH` |
     | Base Resource URL | `https://graph.microsoft.com` |
     | Microsoft Entra ID Resource URI | `https://graph.microsoft.com` |
     | URI | `/v1.0/policies/crossTenantAccessPolicy/partners/{tenantId}` |

     - Body: Restrict inbound/outbound as appropriate
     - Append to `fsi_remediationnotes`: `"Layer 2: CTA partner policy restricted"`

   8c. **Layer 1 — PPAC Tenant Isolation**
   - **Condition:** Finding involves a PPAC allow-list entry
   - **If true:**
     - Attempt to remove tenant from allow-list via PPAC API
     - If API supports deletion: Execute and log
     - If API does not support automated removal: Set `fsi_remediationstatus` = `3` (Deferred) with manual instructions
     - Append to `fsi_remediationnotes`: Layer 1 action taken or deferred

   8d. **Update Finding — Remediated**
   - Action: "Update a record" (Dataverse)
   - Table: `fsi_externalsharefinding`
   - Fields:
     - `fsi_findingstatus`: `2` (Remediated)
     - `fsi_remediationstatus`: `2` (Manually Remediated)
     - `fsi_assignedto`: Approver email
     - `fsi_remediationdate`: Expression `utcNow()`

   8e. **Log Compliance Event**
   - Create `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"External Share Remediated"`

   **If Rejected:**

   8f. **Update Finding — Deferred**
   - Action: "Update a record" (Dataverse)
   - Fields:
     - `fsi_remediationstatus`: `3` (Deferred)
     - `fsi_remediationnotes`: Rejection reason from approver
   - Finding remains in `Open` status

   8g. **Log to Immutable Audit**
   - Create `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Remediation Rejected"`, `fsi_eventdetails` = Rejection reason
   - This event record serves as the immutable audit trail of the decision

### Error Handling

Same scope-based try/catch pattern. For HTTP DELETE/PATCH actions, configure individual **Run after** → Has failed branches that log the error but continue processing remaining layers.

---

## Flow 6: Send-AnnualReviewReminders-Daily

**Type:** Scheduled Cloud Flow
**Trigger:** Recurrence — Daily at 07:00 AM UTC
**Identity:** `MI-CrossTenantReadOnly`
**Purpose:** Send tiered reminder notifications for upcoming and overdue annual reviews of approved external tenants

### Reminder Thresholds

| Threshold | Timing | Recipients | Deduplication Window |
|-----------|--------|------------|---------------------|
| 90-day advance | 90 days before `fsi_annualreviewdue` | `GovernanceTeamEmail` + requesting team | Check `fsi_crosstenantcomplianceevent` for matching event in past 30 days |
| 30-day advance | 30 days before `fsi_annualreviewdue` | `GovernanceTeamEmail` + requesting team + `GovernanceCommitteeUPN` | Check `fsi_crosstenantcomplianceevent` for matching event in past 7 days |
| Overdue | Past `fsi_annualreviewdue` | `GovernanceTeamEmail` + requesting team + `GovernanceCommitteeUPN` | No deduplication — sends daily until resolved |

### Build Steps

1. **Create New Flow**
   - Power Automate → Cloud Flows → Scheduled Cloud Flow
   - Flow name: `Send-AnnualReviewReminders-Daily`
   - Recurrence: Daily at 07:00 UTC

2. **Check Feature Flag**
   - Same pattern as Flow 1, Step 2

3. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `today`: Expression `startOfDay(utcNow())`
   - `ninetyDayWindow`: Expression `addDays(utcNow(), 90)`
   - `thirtyDayWindow`: Expression `addDays(utcNow(), 30)`
   - `governanceTeamEmail`: Environment variable `GovernanceTeamEmail`
   - `governanceCommitteeUpn`: Environment variable `GovernanceCommitteeUPN`
   - `remindersQueued`: Integer `0`

4. **Get All Approved Tenants**
   - Action: "List rows" (Dataverse)
   - Table: `fsi_approvedexternaltenants`
   - Filter: `fsi_approvalstatus eq 1`
   - Select: `fsi_tenantid,fsi_tenantname,fsi_primarydomain,fsi_annualreviewdue,fsi_notes,fsi_requestingteam`

5. **For Each Approved Tenant**
   - Action: Apply to each on approved tenants from Step 4

   5a. **Evaluate 90-Day Threshold**
   - **Condition:** `fsi_annualreviewdue` is less than or equal to `ninetyDayWindow` AND `fsi_annualreviewdue` is greater than `thirtyDayWindow`
   - **If true:**
     1. **Deduplication Check:**
        - Query `fsi_crosstenantcomplianceevent`:
          ```
          fsi_crosstenantcomplianceevents?$filter=fsi_eventtype eq 11 and fsi_eventdetails eq '{tenantId}' and createdon ge {thirtyDaysAgo}&$top=1
          ```
        - **If reminder already sent in past 30 days:** Skip
     2. **If no recent reminder:**
        - Send Teams notification to `governanceTeamEmail` and requesting team (`fsi_notes`):
          - Use Annual Review Reminder Adaptive Card (see [Template 3](#template-3-annual-review-reminder))
          - Set urgency indicator: `"Upcoming"`
        - Create `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Annual Review Due"`, `fsi_eventdetails` = `fsi_tenantid`
        - Increment `remindersQueued`

   5b. **Evaluate 30-Day Threshold**
   - **Condition:** `fsi_annualreviewdue` is less than or equal to `thirtyDayWindow` AND `fsi_annualreviewdue` is greater than `today`
   - **If true:**
     1. **Deduplication Check:**
        - Query for `"Annual Review Due"` events for this tenant in past 7 days
        - **If already sent:** Skip
     2. **If no recent reminder:**
        - Send **URGENT** Teams notification to `governanceTeamEmail`, requesting team, AND `governanceCommitteeUpn`
        - Use Adaptive Card with urgency: `"Urgent"`
        - Create compliance event
        - Increment `remindersQueued`

   5c. **Evaluate Overdue Threshold**
   - **Condition:** `fsi_annualreviewdue` is less than `today`
   - **If true:**
     1. **Create Finding** (no deduplication — daily until resolved):
        - Action: "Create a new record" (Dataverse)
        - Table: `fsi_externalsharefinding`
        - Fields:
          - `fsi_findingtype`: `"Approved Tenant - Review Required"`
          - `fsi_severity`: `3` (Low)
          - `fsi_findingstatus`: `0` (Open)
          - `fsi_externaltenanttenantid`: `fsi_tenantid`
          - `fsi_externaltenantname`: `fsi_primarydomain`
          - `fsi_remediationnotes`: Expression `concat('Annual review overdue since ', fsi_annualreviewdue, ' for tenant ', fsi_tenantname)`
     2. Send **OVERDUE** Teams notification to all three groups (`governanceTeamEmail`, requesting team, `governanceCommitteeUpn`)
     3. Use Adaptive Card with urgency: `"Overdue"` and red accent
     4. Create compliance event with `fsi_eventtype` = `"Annual Review Overdue"`

6. **Check for Expired Onboarding Requests**
   - Query `fsi_approvedexternaltenants` where `fsi_approvalstatus eq 2` (Expired)
   - This data is for alert banner context only — no remediation actions
   - If expired requests exist: Include count in daily summary

7. **Log Daily Summary Event**
   - Create `fsi_crosstenantcomplianceevent` with `fsi_eventtype` = `"Annual Review Completed"`, `fsi_eventdetails` = Expression `concat('Reminders sent: ', remindersQueued)`

### Error Handling

Same scope-based try/catch pattern as Flow 1.

---

## Severity Assignment Reference

| Finding Type | Severity | Code |
|---|---|---|
| Tenant Isolation Disabled | Critical | `0` |
| Unapproved Tenant Isolation Exception | High | `1` |
| Unapproved Guest Share on Zone 3 agent | Critical | `0` |
| Unapproved Guest Share on Zone 2 agent | High | `1` |
| Unapproved Guest Share on Zone 1 agent | Medium | `2` |
| Unapproved Guest Share — zone unknown | High (conservative) | `1` |
| Unapproved B2B Access setting drift | Medium | `2` |
| Approved Tenant — Annual Review Overdue | Low | `3` |

> **Note:** Zone-based severity is derived from `fsi_agentinventory.fsi_zone` (from `agent-registry-automation`). When the zone value is null or the agent is not found in the registry, apply High severity as a conservative default.

---

## Teams Adaptive Card Templates

All cards use Adaptive Cards schema v1.2 with `Action.Submit` (NOT `Action.Execute`).

### Template 1: Daily Scan Summary

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.2",
  "body": [
    {
      "type": "TextBlock",
      "text": "Cross-Tenant Governance — Daily Scan Summary",
      "weight": "Bolder",
      "size": "Large"
    },
    {
      "type": "TextBlock",
      "text": "${ScanDate}",
      "isSubtle": true,
      "spacing": "None"
    },
    {
      "type": "ColumnSet",
      "columns": [
        {
          "type": "Column",
          "width": "stretch",
          "items": [
            {
              "type": "TextBlock",
              "text": "Findings",
              "weight": "Bolder"
            },
            {
              "type": "TextBlock",
              "text": "${TotalFindings}",
              "size": "ExtraLarge",
              "color": "${FindingsColor}"
            }
          ]
        },
        {
          "type": "Column",
          "width": "stretch",
          "items": [
            {
              "type": "TextBlock",
              "text": "Guests Scanned",
              "weight": "Bolder"
            },
            {
              "type": "TextBlock",
              "text": "${GuestsProcessed}",
              "size": "ExtraLarge"
            }
          ]
        },
        {
          "type": "Column",
          "width": "stretch",
          "items": [
            {
              "type": "TextBlock",
              "text": "Environments",
              "weight": "Bolder"
            },
            {
              "type": "TextBlock",
              "text": "${EnvironmentsScanned}",
              "size": "ExtraLarge"
            }
          ]
        }
      ]
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Critical", "value": "${CriticalCount}" },
        { "title": "High", "value": "${HighCount}" },
        { "title": "Medium", "value": "${MediumCount}" },
        { "title": "Low", "value": "${LowCount}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "Tenant Isolation: ${TenantIsolationStatus}",
      "weight": "Bolder",
      "color": "${TenantIsolationColor}"
    },
    {
      "type": "TextBlock",
      "text": "Run ID: ${RunId}",
      "isSubtle": true,
      "size": "Small"
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "View in Compliance Dashboard",
      "url": "${DashboardUrl}"
    }
  ]
}
```

### Template 2: Remediation Approval Request

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.2",
  "body": [
    {
      "type": "TextBlock",
      "text": "⚠️ Remediation Approval Required",
      "weight": "Bolder",
      "size": "Large",
      "color": "Attention"
    },
    {
      "type": "TextBlock",
      "text": "An unauthorized external access finding requires remediation approval.",
      "wrap": true
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Finding Type", "value": "${FindingType}" },
        { "title": "Severity", "value": "${Severity}" },
        { "title": "External Tenant", "value": "${SourceTenantDomain}" },
        { "title": "Agent", "value": "${AgentName}" },
        { "title": "Environment", "value": "${EnvironmentName}" },
        { "title": "Detected", "value": "${DetectedAt}" },
        { "title": "Detection Method", "value": "${GuestDetectionMethod}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "Proposed Remediation Actions:",
      "weight": "Bolder",
      "spacing": "Medium"
    },
    {
      "type": "TextBlock",
      "text": "${RemediationPlan}",
      "wrap": true
    },
    {
      "type": "TextBlock",
      "text": "Finding ID: ${FindingId}",
      "isSubtle": true,
      "size": "Small"
    }
  ],
  "actions": [
    {
      "type": "Action.Submit",
      "title": "Approve Remediation",
      "data": {
        "action": "approve",
        "findingId": "${FindingId}"
      }
    },
    {
      "type": "Action.Submit",
      "title": "Reject (Defer)",
      "data": {
        "action": "reject",
        "findingId": "${FindingId}"
      }
    }
  ]
}
```

### Template 3: Annual Review Reminder

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.2",
  "body": [
    {
      "type": "TextBlock",
      "text": "🔔 External Tenant Annual Review — ${Urgency}",
      "weight": "Bolder",
      "size": "Large",
      "color": "${UrgencyColor}"
    },
    {
      "type": "TextBlock",
      "text": "The following approved external tenant requires annual review.",
      "wrap": true
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Tenant", "value": "${TenantName}" },
        { "title": "Domain", "value": "${PrimaryDomain}" },
        { "title": "Review Due", "value": "${AnnualReviewDue}" },
        { "title": "Days Remaining", "value": "${DaysRemaining}" },
        { "title": "Originally Requested By", "value": "${RequestorUpn}" },
        { "title": "Requesting Team", "value": "${RequestorTeam}" },
        { "title": "Approved Direction", "value": "${ApprovedDirection}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "${UrgencyMessage}",
      "wrap": true,
      "weight": "Bolder",
      "color": "${UrgencyColor}"
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "Start Review in Portal",
      "url": "${ReviewPortalUrl}"
    }
  ]
}
```

**Urgency values:**

| Threshold | `${Urgency}` | `${UrgencyColor}` | `${UrgencyMessage}` |
|-----------|-------------|-------------------|---------------------|
| 90-day | `Upcoming` | `Default` | `"This tenant's annual review is due within 90 days. Please schedule the review."` |
| 30-day | `Urgent` | `Warning` | `"This tenant's annual review is due within 30 days. Immediate scheduling is recommended."` |
| Overdue | `Overdue` | `Attention` | `"This tenant's annual review is OVERDUE. A finding has been created. Review and re-approve or revoke access immediately."` |

### Template 4: Tenant Onboarding Security Attestation

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.2",
  "body": [
    {
      "type": "TextBlock",
      "text": "🔐 External Tenant Onboarding — Security Review",
      "weight": "Bolder",
      "size": "Large"
    },
    {
      "type": "TextBlock",
      "text": "A new external tenant onboarding request requires security team approval.",
      "wrap": true
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Requested Tenant", "value": "${TenantName}" },
        { "title": "Tenant ID", "value": "${TenantId}" },
        { "title": "Domain", "value": "${PrimaryDomain}" },
        { "title": "Requested Direction", "value": "${RequestedDirection}" },
        { "title": "Requestor", "value": "${RequestorUpn}" },
        { "title": "Requesting Team", "value": "${RequestorTeam}" },
        { "title": "Request Date", "value": "${RequestDate}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "Business Justification:",
      "weight": "Bolder",
      "spacing": "Medium"
    },
    {
      "type": "TextBlock",
      "text": "${BusinessJustification}",
      "wrap": true
    },
    {
      "type": "TextBlock",
      "text": "${TenantMismatchWarning}",
      "wrap": true,
      "color": "Attention",
      "isVisible": "${ShowMismatchWarning}"
    },
    {
      "type": "TextBlock",
      "text": "Security Attestation Checklist:",
      "weight": "Bolder",
      "spacing": "Medium"
    },
    {
      "type": "TextBlock",
      "text": "By approving, you attest that:\n- The external tenant has been verified\n- Data sharing risks have been assessed\n- The requested direction is appropriate\n- Annual review cadence is accepted",
      "wrap": true
    },
    {
      "type": "TextBlock",
      "text": "Request ID: ${RequestId}",
      "isSubtle": true,
      "size": "Small"
    }
  ],
  "actions": [
    {
      "type": "Action.Submit",
      "title": "Approve — Security Cleared",
      "data": {
        "action": "approve",
        "requestId": "${RequestId}",
        "approvalType": "security"
      }
    },
    {
      "type": "Action.Submit",
      "title": "Reject",
      "data": {
        "action": "reject",
        "requestId": "${RequestId}",
        "approvalType": "security"
      }
    }
  ]
}
```

### Template 5: Tenant Onboarding Governance Approval

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.2",
  "body": [
    {
      "type": "TextBlock",
      "text": "📋 External Tenant Onboarding — Governance Review",
      "weight": "Bolder",
      "size": "Large"
    },
    {
      "type": "TextBlock",
      "text": "A new external tenant onboarding request requires governance committee approval.",
      "wrap": true
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Requested Tenant", "value": "${TenantName}" },
        { "title": "Tenant ID", "value": "${TenantId}" },
        { "title": "Domain", "value": "${PrimaryDomain}" },
        { "title": "Requested Direction", "value": "${RequestedDirection}" },
        { "title": "Requestor", "value": "${RequestorUpn}" },
        { "title": "Requesting Team", "value": "${RequestorTeam}" },
        { "title": "Request Date", "value": "${RequestDate}" },
        { "title": "Annual Review Due", "value": "${AnnualReviewDue}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "Business Justification:",
      "weight": "Bolder",
      "spacing": "Medium"
    },
    {
      "type": "TextBlock",
      "text": "${BusinessJustification}",
      "wrap": true
    },
    {
      "type": "TextBlock",
      "text": "${TenantMismatchWarning}",
      "wrap": true,
      "color": "Attention",
      "isVisible": "${ShowMismatchWarning}"
    },
    {
      "type": "TextBlock",
      "text": "Security Team Status: ${SecurityApprovalStatus}",
      "weight": "Bolder",
      "spacing": "Medium"
    },
    {
      "type": "TextBlock",
      "text": "Governance Review Scope:",
      "weight": "Bolder",
      "spacing": "Medium"
    },
    {
      "type": "TextBlock",
      "text": "By approving, the governance committee confirms:\n- The business relationship justifies cross-tenant access\n- The access direction and scope are appropriate\n- The requesting team accepts responsibility for annual review\n- Regulatory obligations (if applicable) have been considered",
      "wrap": true
    },
    {
      "type": "TextBlock",
      "text": "Request ID: ${RequestId}",
      "isSubtle": true,
      "size": "Small"
    }
  ],
  "actions": [
    {
      "type": "Action.Submit",
      "title": "Approve — Governance Cleared",
      "data": {
        "action": "approve",
        "requestId": "${RequestId}",
        "approvalType": "governance"
      }
    },
    {
      "type": "Action.Submit",
      "title": "Reject",
      "data": {
        "action": "reject",
        "requestId": "${RequestId}",
        "approvalType": "governance"
      }
    }
  ]
}
```

---

## Testing Checklist

After building all flows:

- [ ] Feature flag check — set `IsCrossTenantGovernanceEnabled` to `"false"` and verify all flows terminate gracefully
- [ ] Flow 1 — Run manually; verify `fsi_tenantisolationrecord` created with snapshot
- [ ] Flow 1 — Disable tenant isolation in test environment; verify Critical finding created
- [ ] Flow 2 — Run manually; verify guest users detected and domain resolution works
- [ ] Flow 2 — Confirm zone-based severity from `fsi_agentinventory.fsi_zone`
- [ ] Flow 2 — Verify deduplication prevents duplicate Open findings
- [ ] Flow 3 — Run manually; verify `fsi_entractarecord` created
- [ ] Flow 3 — Modify baseline env var to force drift finding
- [ ] Flow 4 — Submit test onboarding request; verify dual-approval flow
- [ ] Flow 4 — Let approval expire; verify Expired status set
- [ ] Flow 4 — Reject from one approver; verify Revoked status
- [ ] Flow 5 — Trigger with test finding; verify approval card sent
- [ ] Flow 5 — Approve remediation; verify Layer 3 action executed
- [ ] Flow 5 — Test "Tenant Isolation Disabled" path; verify Deferred status
- [ ] Flow 6 — Set review dates to trigger each threshold (90-day, 30-day, overdue)
- [ ] Flow 6 — Verify deduplication prevents repeat 90-day reminders within 30 days
- [ ] Teams Adaptive Cards render correctly in desktop and mobile clients
- [ ] All compliance events logged to `fsi_crosstenantcomplianceevent`

## Troubleshooting

**Issue: Graph API returns 403 for guest user queries**
- **Cause:** Managed Identity lacks `User.Read.All` permission
- **Resolution:** Grant `User.Read.All` (application) permission to `MI-CrossTenantReadOnly` in Entra ID → App registrations → API permissions

**Issue: PPAC tenant settings API returns unexpected schema**
- **Cause:** API version may have changed or the `api-version` parameter is outdated
- **Resolution:** Verify the API version in the URI. Flow 1 Step 4 includes schema validation that alerts `FlowAdministrators` when the expected property is missing. Update the URI parameter if Microsoft publishes a new API version.

**Issue: Guest UPN parsing fails for MSA guests**
- **Cause:** Microsoft Account (MSA) guests use `live.com`, `outlook.com`, or `hotmail.com` domains which follow different UPN encoding
- **Resolution:** The 5-value detection method in Flow 2 Step 6 handles MSA guests by flagging them in `fsi_remediationnotes`. If MSA guests are legitimate in your environment, add their domains to an exclusion list in the flow logic.

**Issue: Dual-approval timeout fires before both approvers respond**
- **Cause:** The `P10D` timeout counts calendar days, not business days. Weekends and holidays reduce effective response time.
- **Resolution:** Adjust the timeout value in Flow 4 Step 9 based on your organization's approval SLA. Consider `P14D` for organizations with slower approval cycles.

**Issue: Annual review reminders send repeatedly for the same tenant**
- **Cause:** Deduplication check query may not match if `fsi_eventdetails` content changed between runs
- **Resolution:** Verify the `fsi_eventdetails` field in the deduplication query uses the exact `fsi_tenantid` value. The 90-day check uses a 30-day deduplication window; the 30-day check uses a 7-day window.
