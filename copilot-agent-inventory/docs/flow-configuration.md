# Copilot Agent Inventory - Flow Setup Guide

## Overview

Step-by-step guide for building the Power Automate flow that schedules the daily
Copilot Agent Inventory discovery scan and records each run for audit purposes.

This guide covers one flow:

1. **CAI-DailyDiscovery** — daily scheduled, tenant-wide discovery scan that
   executes the scanner, persists the inventory to Dataverse, and writes a run
   record.

> **Important:** These are manual build instructions. This solution does **not**
> include exported flow JSON, connection references, or environment-variable
> exports. Build the flow in the Power Automate designer following the steps
> below. This keeps the solution free of fragile cross-file references and lets
> administrators adapt the flow to their environment.

> **Persistence contract:** The discovery scanner emits a combined JSON file
> (via `--output`) and does **not** itself write to Dataverse. The scanner emits
> option-set fields as LABEL strings (e.g. `"Paid Copilot"`, `"Reconciled (multi-source)"`);
> this flow converts each label to its Dataverse option-set integer via Compose
> actions before writing (see Step 7a below). This flow reads the scanner
> JSON output, iterates over `agents[]` to reconcile each record into
> `fsi_copilotagent` (including all new package, owner, and entitlement fields),
> and then writes **exactly one** `fsi_caiscanrun` run-ledger row (Step 8). The
> validated connector pattern is **List rows -> Add when missing -> capture the
> primary GUID -> Update a row by GUID**. All Dataverse persistence is the
> responsibility of this flow.

## Prerequisites

Before creating the flow, confirm you have:

- [ ] **Azure Automation Account** (or an Azure Function / hosted runner) with:
  - The discovery scanner (`scripts/discover_agents.py`) deployed as a runnable
    job, running under a **managed identity** (system- or user-assigned).
  - Python 3.9+ and the packages in `scripts/requirements.txt` available to the
    job.
- [ ] **Dataverse environment** with the CAI schema deployed:
  - 9 tables: `fsi_copilotagent`, `fsi_caienvironment`, `fsi_caiagentfeature`,
    `fsi_caiauthshare`, `fsi_caibillingentitlement`, `fsi_caiusagesignal`,
    `fsi_caiworkiqstate`, `fsi_caicompliancestate`, `fsi_caiscanrun`.
- [ ] **Scanner service principal** (read-only) with the roles and scopes in
  [prerequisites.md](prerequisites.md) — environment enumeration + per-environment
  `bot` / `botcomponent` **read only**. The scanner emits JSON and does **not**
  write to Dataverse.
- [ ] **Flow-writer identity** — the Power Automate **Dataverse connection** this
  flow uses holds **Create / Write** on the CAI tables in the governance
  environment. This is the **only** identity that writes the inventory (see the
  three-identity split in [prerequisites.md](prerequisites.md#roles-and-permissions-the-three-governance-identities)).
- [ ] **Microsoft Teams** channel and/or an **email distribution list** for
  run notifications (optional).
- [ ] **Connection references** bound in Power Automate (create these in the
  designer when you add each action; names below are a suggested convention):
  - `fsi_cr_dataverse_copilotagentinventory` (Dataverse)
  - `fsi_cr_teams_copilotagentinventory` (Microsoft Teams, optional)
  - An Azure Automation (or Azure Function) connection.

---

## Flow: CAI-DailyDiscovery

### Purpose

Runs daily, executes the discovery scanner across the tenant, writes the
normalized inventory to the CAI Dataverse tables, and records a run summary. A
durable run record supports compliance with the record-keeping expectations of
FINRA Rule 4511 and SEC Rule 17a-3/17a-4 — the run summary is written regardless
of whether notification succeeds.

### Step 1: Create the Flow

1. Go to [make.powerautomate.com](https://make.powerautomate.com).
2. Select your governance environment.
3. Click **Create** > **Scheduled cloud flow**.
4. Name: `CAI - Copilot Agent Discovery (Daily)`.
5. Set schedule:
   - Repeat every: **1 Day**.
   - At: **5:00 AM**.
   - Time zone: **UTC**.
6. Click **Create**.

> **Cadence note:** ARG inventory freshness is roughly 15 minutes, so a daily
> scan is well within data-freshness limits. Adjust the cadence to your
> examination and change-tracking needs.

### Step 2: Initialize Variables

Add these **Initialize variable** actions immediately after the trigger. Replace
the placeholders (`{{...}}`) with your organization's values.

| Variable | Type | Default Value | Description |
|----------|------|---------------|-------------|
| `RunStartedAt` | String | `utcNow()` | Run-start timestamp captured at flow start (written to `fsi_startedat`). Initialize this **first**, before Step 3 — the scanner JSON does not carry its own run timing. |
| `GovernanceDataverseUrl` | String | `https://governance.crm.dynamics.com` | Dataverse environment hosting the CAI tables |
| `TenantId` | String | `{{TENANT_DOMAIN}}` | Microsoft Entra ID tenant identifier |
| `Agent365Mode` | String | `absent` | Agent 365 / Layer 4 mode. Accepted values: **`present`**, **`absent`** (default), **`auto`**. Passed to the scanner as `--agent365 <Agent365Mode>`. Leave at `absent` unless the operator has authoritatively scoped in Agent 365 (see [prerequisites.md](prerequisites.md#package-management-api-layer-4-prerequisites)). |
| `SubscriptionId` | String | `{{AZURE_SUBSCRIPTION}}` | Azure subscription containing the Automation Account |
| `ResourceGroup` | String | `{{RESOURCE_GROUP}}` | Resource group with the Automation Account |
| `AutomationAccount` | String | `{{AUTOMATION_ACCOUNT}}` | Azure Automation Account name |
| `TeamsGroupId` | String | `{{TEAMS_GROUP_ID}}` | Teams group ID for run notifications (optional) |
| `TeamsChannelId` | String | `{{TEAMS_CHANNEL_ID}}` | Teams channel ID for run notifications (optional) |
| `UnmappedRows` | Array | `[]` | Sanitized keyless-row and unknown-Choice-label errors collected across agent and run-ledger persistence |

> **`Agent365Mode` is an operator declaration.** Validate it to exactly one of
> `present` / `absent` / `auto` before Step 3 (add a **Condition** or a small
> **Switch** that terminates on any other value). The scanner also enforces the
> value, but validating in the flow keeps a misconfigured variable from starting
> a job. Do **not** prompt interactively — the mode is chosen here, in the flow
> variable, once.

> **Integrated scanner additional variables** (add when using `--registry-export`):
> `RegistryExportPath` (String — path to the XLSX or CSV registry export),
> `ColumnMapPath` (String — default `templates/registry-columnmap.sample.json`),
> `AsOfDateTime` (String — ISO-8601 UTC as-of timestamp for the export, e.g.
> `2026-07-21T18:00:00Z`).

> **No secrets in variables.** The scanner authenticates with its managed
> identity. Do not place client secrets in flow variables; if a dev-only secret
> is unavoidable, the scanner reads it from Key Vault at runtime.

### Step 3: Execute the Discovery Scanner

1. Add action: **Azure Automation** > **Create job** (or the equivalent
   Azure Function action).
2. Configure:
   - Subscription: `SubscriptionId` variable.
   - Resource Group: `ResourceGroup` variable.
   - Automation Account: `AutomationAccount` variable.
   - Runbook / job: the wrapper that invokes the integrated scanner. For the
     full BI-ready combined output (agents[] + registryCorrelation +
     entitlementResolution):
     ```
     python scripts/discover_agents.py \
       --tenant-id <TenantId> \
       --auth-mode managed-identity \
       --agent365 <Agent365Mode> \
       --registry-export <RegistryExportPath> \
       --columnmap <ColumnMapPath> \
       --as-of <AsOfDateTime> \
       --resolve-entitlement \
       --output scan.json
     ```
     Set `Agent365Mode` to `absent` (default) to defer Layer 4; the run still
     inventories available agents and marks the Package API `Deferred` (never
     an observed zero). ARG can classify Agent Builder agents through
     `createdIn`; Layer 2 does not supply that field. Set the mode to `present`
     to attempt the Package API, or `auto` to license-probe first. Omit
     `--registry-export` (and
     related flags) to run without registry correlation; the output is
     backward-compatible when these flags are absent.
3. Rename action: `Create_Discovery_Job`.

### Step 4: Wait for Job Completion

1. Add action: **Azure Automation** > **Wait for job**.
2. Configure:
   - Job ID: `Create_Discovery_Job` output `jobId`.
   - Timeout: 7200 seconds (2 hours) — raise for very large tenants.
   - Polling interval: 60 seconds.
3. Rename action: `Wait_For_Job`.

### Step 5: Get Job Output

1. Add action: **Azure Automation** > **Get job output**.
2. Configure: Job ID = the same `jobId`.
3. Rename action: `Get_Job_Output`.

### Step 6: Parse the Scan Summary

1. Add action: **Data Operations** > **Parse JSON**.
2. Content: `Get_Job_Output` output (the full scanner JSON — top-level keys are
   `summary`, `agents`, `features`, and `authShares`).
3. Schema (matches the full `discover_agents.py scan_all` combined output;
   `runId` and all counts live inside `summary`, `agents` is top-level):

```json
{
    "type": "object",
    "properties": {
        "summary": {
            "type": "object",
            "properties": {
                "runId": { "type": "string" },
                "status": { "type": "string" },
                "environmentEnumeration": {
                    "type": "object",
                    "properties": {
                        "status": { "type": "string" },
                        "environmentCount": { "type": "integer" },
                        "dataverseEnvironmentCount": { "type": "integer" },
                        "skippedNoDataverseCount": { "type": "integer" },
                        "httpStatus": { "type": ["integer", "null"] },
                        "reason": { "type": "string" }
                    }
                },
                "argLayer": {
                    "type": "object",
                    "properties": {
                        "status": { "type": "string" },
                        "agentCount": { "type": "integer" },
                        "httpStatus": { "type": ["integer", "null"] }
                    }
                },
                "environmentFailures": {
                    "type": "array",
                    "items": { "type": "object" }
                },
                "argAgentCount": { "type": "integer" },
                "scannedAgentCount": { "type": "integer" },
                "coreAgentCount": { "type": "integer" },
                "featureCount": { "type": "integer" },
                "authShareCount": { "type": "integer" },
                "environmentCount": { "type": "integer" },
                "packageNewRowCount": { "type": "integer" },
                "packageScanTruncated": { "type": "boolean" },
                "reconciliation": {
                    "type": "object",
                    "properties": {
                        "in_arg_only": { "type": "array" },
                        "in_dataverse_only": { "type": "array" },
                        "in_both": { "type": "array" }
                    }
                },
                "registryCorrelation": {
                    "type": "object",
                    "properties": {
                        "registryRowCount": { "type": "integer" },
                        "matched": { "type": "integer" },
                        "unmatchedRegistryRows": { "type": "integer" },
                        "ambiguousNameSkipped": { "type": "integer" },
                        "invalidDateWarnings": { "type": "integer" },
                        "status": { "type": "string" }
                    }
                },
                "entitlementResolution": {
                    "type": "object",
                    "properties": {
                        "ownersConsidered": { "type": "integer" },
                        "paidCount": { "type": "integer" },
                        "chatOnlyCount": { "type": "integer" },
                        "unknownCount": { "type": "integer" },
                        "status": { "type": "string" }
                    }
                },
                "agent365": {
                    "type": "object",
                    "properties": {
                        "requestedMode": { "type": "string" },
                        "resolvedState": { "type": "string" },
                        "resolutionSource": { "type": "string" },
                        "detectionConfidence": { "type": "string" },
                        "licenseProbeAttempted": { "type": "boolean" },
                        "packageApiAttempted": { "type": "boolean" },
                        "layerStatus": { "type": "string" },
                        "httpStatus": { "type": ["integer", "null"] },
                        "errorCode": { "type": ["string", "null"] },
                        "errorSubcode": { "type": ["string", "null"] },
                        "reason": { "type": ["string", "null"] },
                        "packagesObserved": { "type": ["integer", "null"] },
                        "packageNewRowCount": { "type": ["integer", "null"] },
                        "pagingTruncated": { "type": "boolean" }
                    }
                },
                "coverageScope": {
                    "type": "object",
                    "properties": {
                        "layers": {
                            "type": "object",
                            "properties": {
                                "arg": { "type": "string" },
                                "environmentDataverse": { "type": "string" },
                                "packageApi": { "type": "string" },
                                "registry": { "type": "string" },
                                "entitlement": { "type": "string" }
                            }
                        },
                        "authoritativeFor": { "type": "array", "items": { "type": "string" } },
                        "limitations": { "type": "array", "items": { "type": "string" } },
                        "warning": { "type": "string" }
                    }
                }
            }
        },
        "agents": {
            "type": "array",
            "items": { "type": "object" }
        },
        "features": { "type": "array" },
        "authShares": { "type": "array" }
    }
}
```

4. Rename action: `Parse_Summary`.

> **Scan-completeness signals (read before persisting).** The scanner reports
> whether the run is trustworthy through four summary fields. Use them to decide
> whether to alert (Step 9) — a partial or authorization-blocked scan must never be
> treated as a clean, empty tenant:
>
> - `summary.status` — `Complete` / `Incomplete` / `Failed` (overall).
> - `summary.environmentEnumeration.status` — `Success` / `Failed` / `Dry Run`.
>   A `Failed` value means the environment list itself could not be read (for
>   example a 401/403), so **zero environments is a failure, not an empty tenant**.
> - `summary.argLayer.status` — `Available` / `Unavailable` / `Failed` / `Disabled`.
>   `Failed` is distinct from `Available` with `agentCount: 0` (a genuine zero).
> - `summary.environmentFailures[]` — one record per per-environment coverage gap
>   (`environmentId`, `stage`, `httpStatus`, `reason`). An empty array is a clean run.

> **Parse `summary.agent365` and `summary.coverageScope` on every run.** They are
> always present, and Step 8 persists them to `fsi_caiscanrun`:
>
> - `summary.agent365.resolvedState` — `Present` / `Absent` / `NotDetected` /
>   `Inconclusive`. `summary.agent365.layerStatus` — `Full` / `Deferred` /
>   `Unsupported` / `Partial` / `Failed` / `Dry Run`.
> - **`Deferred` and heuristic `NotDetected` are informational, not failures**
>   (see Step 9). A `Deferred` Layer 4 is **never** "zero Agent Builder agents";
>   it means the package catalog was not observed. Agent Builder classification
>   still comes from ARG when `createdIn` is available; Layer 2 inventory alone
>   leaves the authoring surface unknown.
> - **Null vs zero for package counts.** `summary.agent365.packagesObserved` and
>   `packageNewRowCount` are **`null`** when the Package API was **not observed**
>   (deferred / not attempted) and **`0`** when it **was** attempted and returned
>   an **empty** catalog. Preserve the distinction when mapping to Dataverse in
>   Step 8 — write `null`, not `0`, for a deferred layer.
> - `summary.coverageScope.layers` names each layer's status
>   (`layers.arg` / `layers.environmentDataverse` / `layers.packageApi` /
>   `layers.registry` / `layers.entitlement`), alongside
>   `coverageScope.authoritativeFor`, `coverageScope.limitations`, and a
>   `coverageScope.warning` that a `Deferred` / `NotDetected` Layer 4 is not an
>   authoritative Agent Builder catalog.

### Step 7: Persist Agent Records to Dataverse

The scanner emits each discovered agent as an object in `agents[]`. Use an
**Apply to each** action to reconcile every agent row into `fsi_copilotagent`.

> **Connector behavior validated live.** The Dataverse connector's **Update a
> row** action executes an update against its Row ID. Supplying an alternate-key
> value does not create a missing row; the observed connector returned HTTP 404.
> Use the lookup/create/GUID-update sequence below rather than treating **Update
> a row** as an alternate-key upsert.

1. Before the loop, initialize a String variable named `AgentRowId` and a
   Boolean variable named `IsUnmappedLabel`.
2. Add action: **Control** > **Apply to each**.
3. Select output: expression `body('Parse_Summary')?['agents']` (the top-level
   `agents` array from the full scanner output; `agents` is **not** nested inside
   `summary`).
4. Set **Apply to each** concurrency to **Off** (or degree `1`). The flow uses the
   shared `AgentRowId` variable, so parallel iterations can update the wrong row.
5. Inside the loop, reset `AgentRowId` to an empty string and
   `IsUnmappedLabel` to `false`. Complete every Step 7a Choice mapping
   **before** any List rows, Add, or Update action. If any mapping Compose
   returns `-1`, quarantine the row and skip the persistence branches.
6. Add a
   **Condition** action to select the correct key using this deterministic
   precedence:

   * **Branch A — environment-scoped rows (PRIMARY)** — when both
     `fsi_agentid` and `fsi_environmentid` are populated:
     1. Add **Dataverse** > **List rows** for `fsi_copilotagent`.
     2. Filter on both key columns:
        `fsi_agentid eq '<current fsi_agentid>' and fsi_environmentid eq '<current fsi_environmentid>'`.
        Set **Row count** to `1` and select only `fsi_copilotagentid`.
     3. If the returned `value` array is non-empty, set `AgentRowId` to
        `first(body('List_Agent_By_Env_Key')?['value'])?['fsi_copilotagentid']`.
     4. Otherwise, add **Dataverse** > **Add a new row** with:
        - `fsi_name` and `fsi_agentname` set to the agent name, falling back to
          `fsi_agentid`;
        - `fsi_agentid` and `fsi_environmentid` from the current item;
        - `fsi_lastscannedat` set to `utcNow()`;
        - `fsi_runid` from the current item.
        Then set `AgentRowId` from the created row's `fsi_copilotagentid`.

   * **Branch B — package-only rows (FALLBACK)** — when Branch A does not apply
     and `fsi_packageid` is populated:
     1. Add **Dataverse** > **List rows** for `fsi_copilotagent`.
     2. Filter on `fsi_packageid eq '<current fsi_packageid>'`. Set **Row
        count** to `1` and select only `fsi_copilotagentid`.
     3. If the returned `value` array is non-empty, set `AgentRowId` to the
        first row's `fsi_copilotagentid`.
     4. Otherwise, add **Dataverse** > **Add a new row** with:
        - `fsi_name` and `fsi_agentname` set to the package display name,
         falling back to `fsi_packageid`;
        - `fsi_agentid` and `fsi_packageid` set to the package ID;
        - `fsi_lastscannedat` set to `utcNow()`;
        - `fsi_runid` from the current item.
        Then set `AgentRowId` from the created row's `fsi_copilotagentid`.
     5. Do **not** supply `fsi_environmentid`; package-only rows have no
        environment scope.

   * **Branch C — unpersistable rows (ERROR)** — when neither condition is
     true, add a **Terminate** action (status: Failed) or append the row to an
     error collection variable for post-run review. Do **not** add a generic
     **Add a new row** action without an idempotency key.

   Both alternate keys must reach `Active` before scheduled persistence begins.
   The keys protect uniqueness, but the connector lookup and create operations
   are not atomic. Configure trigger concurrency to allow only one active flow
   run; overlapping runs can cause one run to fail on an alternate-key collision
   even though duplicate rows are blocked.

   > **Existing v0.4 preview deployments:** fresh deployments define
   > `fsi_environmentid` as optional because package-only rows have no
   > environment. The schema deployer skips metadata for columns that already
   > exist. If an earlier preview deployment still shows **Environment ID** as
   > Business Required, change its Requirement to **Optional** in the Dataverse
   > table designer and publish before authoring Branch B.

7. After Branch A or B sets `AgentRowId`, add **Dataverse** > **Update a row**.
   Table: `fsi_copilotagent`. Set **Row ID** to `variables('AgentRowId')`.
8. Map the columns below. Use `items('Apply_to_each')` to reference the current
   agent object. All column names are Dataverse **logical** names (lowercase, no
   underscores between words).

| Flow Expression | Dataverse Column (logical) | Type | Notes |
|----------------|----------------------------|------|-------|
| `coalesce(items('Apply_to_each')?['fsi_agentname'], items('Apply_to_each')?['fsi_agentid'], items('Apply_to_each')?['fsi_packageid'])` | `fsi_name` | String | Required Dataverse primary name; also set during **Add a new row** |
| `coalesce(items('Apply_to_each')?['fsi_agentid'], items('Apply_to_each')?['fsi_packageid'])` | `fsi_agentid` | String | Agent ID; package-only rows use the package ID. PRIMARY key component of fsi_AgentEnvKey for Branch A |
| `items('Apply_to_each')?['fsi_environmentid']` | `fsi_environmentid` | String | PRIMARY key component of fsi_AgentEnvKey; present for environment-scoped and package-enriched rows (Branch A); absent for package-only rows (Branch B) |
| `coalesce(items('Apply_to_each')?['fsi_agentname'], items('Apply_to_each')?['fsi_agentid'], items('Apply_to_each')?['fsi_packageid'])` | `fsi_agentname` | String | Required display name |
| `utcNow()` | `fsi_lastscannedat` | DateTime | Required refresh timestamp; update on every run |
| `items('Apply_to_each')?['fsi_runid']` | `fsi_runid` | String | Correlates the current agent state to `fsi_caiscanrun` |
| `items('Apply_to_each')?['fsi_agenttype']` | `fsi_agenttype` | Choice | Agent type; convert label to integer — see Step 7a |
| `items('Apply_to_each')?['fsi_createdin']` | `fsi_createdin` | Choice | Platform origin; convert label to integer — see Step 7a |
| `items('Apply_to_each')?['fsi_discoverysource']` | `fsi_discoverysource` | Picklist | Discovery layer |
| `items('Apply_to_each')?['fsi_packageid']` | `fsi_packageid` | String | Package API id (`P_...`); FALLBACK key for fsi_PackageKey alternate key; used only when fsi_agentid or fsi_environmentid is absent (Branch B — package-only rows) |
| `items('Apply_to_each')?['fsi_packagetype']` | `fsi_packagetype` | String | microsoft / external / shared / custom |
| `items('Apply_to_each')?['fsi_elementtypes']` | `fsi_elementtypes` | Memo | JSON array (Bots / DeclarativeAgent / CustomEngineAgent) |
| `items('Apply_to_each')?['fsi_isblocked']` | `fsi_isblocked` | Boolean | Package blocked flag |
| `items('Apply_to_each')?['fsi_packageversion']` | `fsi_packageversion` | String | Package version |
| `items('Apply_to_each')?['fsi_assetid']` | `fsi_assetid` | String | Package asset id |
| `items('Apply_to_each')?['fsi_publisher']` | `fsi_publisher` | String | Publisher name |
| `items('Apply_to_each')?['fsi_supportedhosts']` | `fsi_supportedhosts` | Memo | JSON array of host surfaces |
| `items('Apply_to_each')?['fsi_availableto']` | `fsi_availableto` | Choice | Availability scope (None / Some / All); convert label to integer — see Step 7a |
| `items('Apply_to_each')?['fsi_deployedto']` | `fsi_deployedto` | Choice | Deployment scope (None / Some / All); convert label to integer — see Step 7a |
| `items('Apply_to_each')?['fsi_manifestid']` | `fsi_manifestid` | String | Manifest id |
| `items('Apply_to_each')?['fsi_manifestversion']` | `fsi_manifestversion` | String | Manifest version |
| `items('Apply_to_each')?['fsi_ownerupn']` | `fsi_ownerupn` | String | Owner UPN (registry-sourced; never the creator) |
| `items('Apply_to_each')?['fsi_ownerid']` | `fsi_ownerid` | String | Owner Entra object GUID |
| `items('Apply_to_each')?['fsi_createdon']` | `fsi_createdon` | DateTime | Registry-recorded creation date |
| `items('Apply_to_each')?['fsi_ownersource']` | `fsi_ownersource` | Picklist | Owner data provenance |
| `items('Apply_to_each')?['fsi_ownermatchconfidence']` | `fsi_ownermatchconfidence` | Picklist | Exact / Heuristic / Unmatched |
| `items('Apply_to_each')?['fsi_ownerasofdatetime']` | `fsi_ownerasofdatetime` | DateTime | Export as-of timestamp (staleness signal) |
| `items('Apply_to_each')?['fsi_ownerentitlement']` | `fsi_ownerentitlement` | Picklist | Paid Copilot / Copilot Chat Only / Unknown |
| `items('Apply_to_each')?['fsi_ownerentitlementevidence']` | `fsi_ownerentitlementevidence` | Memo | Service-plan GUIDs as JSON array (no PII) |

> **Column naming:** always use Dataverse **logical** names (lowercase, no
> underscores between words) in flow column mappings — for example
> `fsi_agentid`, `fsi_ownerupn`, `fsi_packagetype`. See
> [dataverse-schema.md](dataverse-schema.md) for the authoritative list.

9. Configure **Run after**: `Parse_Summary` — set to **Succeeded**.
10. Rename the loop `Persist_Agent_Records` and the common GUID update action
   `Update_Agent_Record`.
11. After the loop, add `Validate_Agent_Persistence`. If `UnmappedRows` contains
   any entry (from an unknown Choice label or a keyless row), send a sanitized
   notification and terminate as Failed before writing the scan-run ledger.

#### Step 7a — Label-to-Integer Conversion for Choice Fields

At Step 7.5, before any lookup or write, add a **Compose** action for each Choice
column to convert the scanner's label string to the Dataverse option-set integer.
The scanner emits labels; Dataverse requires integers. `fsi_isblocked` is a
Two-Options (Boolean) field — pass `true` / `false` directly.

| Choice Column (logical name) | Scanner Label | Dataverse Integer |
|---|---|---|
| `fsi_discoverysource` | `Azure Resource Graph` | `100000000` |
| `fsi_discoverysource` | `Per-Environment Dataverse Scan` | `100000001` |
| `fsi_discoverysource` | `PPAC Reconciliation` | `100000002` |
| `fsi_discoverysource` | `Reconciled (multi-source)` | `100000003` |
| `fsi_discoverysource` | `Package Management API` | `100000004` |
| `fsi_createdin` | `Copilot Studio` | `100000000` |
| `fsi_createdin` | `Microsoft 365 Copilot Agent Builder` | `100000001` |
| `fsi_createdin` | `Unknown` | `100000002` |
| `fsi_agenttype` | `Standard` | `100000000` |
| `fsi_agenttype` | `Lite / Agent Builder` | `100000001` |
| `fsi_agenttype` | `Declarative Agent` | `100000002` |
| `fsi_agenttype` | `Classic V1 (excluded)` | `100000003` |
| `fsi_agenttype` | `Unknown` | `100000004` |
| `fsi_agenttype` | `Custom Engine Agent` | `100000005` |
| `fsi_availableto` | `None` | `100000000` |
| `fsi_availableto` | `Some` | `100000001` |
| `fsi_availableto` | `All` | `100000002` |
| `fsi_deployedto` | `None` | `100000000` |
| `fsi_deployedto` | `Some` | `100000001` |
| `fsi_deployedto` | `All` | `100000002` |
| `fsi_ownerentitlement` | `Paid Copilot` | `100000000` |
| `fsi_ownerentitlement` | `Copilot Chat Only` | `100000001` |
| `fsi_ownerentitlement` | `Unknown` | `100000002` |
| `fsi_ownersource` | `Dataverse Owner` | `100000000` |
| `fsi_ownersource` | `Agent Registry Export` | `100000001` |
| `fsi_ownersource` | `Unresolved` | `100000002` |
| `fsi_ownermatchconfidence` | `Exact` | `100000000` |
| `fsi_ownermatchconfidence` | `Heuristic` | `100000001` |
| `fsi_ownermatchconfidence` | `Unmatched` | `100000002` |

> **Implementation pattern:** use a nested `if(...)` expression in each Compose.
> Return `json('null')` when an optional source label is empty, the listed
> integer for a known label, and `-1` for a non-empty unknown label. For example,
> `Map_DiscoverySource` starts with:
>
> `if(empty(items('Apply_to_each')?['fsi_discoverysource']), json('null'), if(equals(items('Apply_to_each')?['fsi_discoverysource'], 'Azure Resource Graph'), 100000000, ... -1))`
>
> Compose outputs are evaluated independently for each loop iteration, so a null
> value cannot reuse an integer from the prior agent. After all mapping Composes,
> add a Condition that checks whether any output equals `-1`. If so, set
> `IsUnmappedLabel` to `true`, append the row and offending label to
> `UnmappedRows`, and skip the key-selection/persistence branches. Reference the
> Compose outputs in the final **Update a row by GUID** mapping.
>
> A non-empty unknown label almost always indicates platform drift. Do not map it
> to `0`, the first option, or null; those choices would record an incorrect or
> missing governance signal.
>
> **Keyless / unmapped rows are never inserted.** A row is persisted only when it
> resolves a valid alternate key (Branch A `fsi_AgentEnvKey` or Branch B
> `fsi_PackageKey`) **and** every Choice label mapped to a known integer. Rows that
> hit Branch C (no key) or a `-1` mapping result (unmapped label) are routed to the error
> collection / Terminate path — never written with a generic **Add a new row** action
> and never written with a guessed default option value. This helps keep the
> inventory free of unkeyed duplicates and mislabelled governance signals.

---

### Step 8: Write the single Run-Ledger Record (`fsi_caiscanrun`)

> **Why this runs before notification:** the run record is written regardless of
> whether notification succeeds, supporting compliance with the record-keeping
> expectations of FINRA Rule 4511 and SEC Rule 17a-3.

After all agent rows are persisted (Step 7), reconcile **exactly one** row in the
canonical run-ledger table **`fsi_caiscanrun`**.

1. Before the Scope, initialize a String variable named `ScanRunRowId`.
2. Add a Scope named `Persist_And_Verify_Scan_Run`. Inside it, complete every
   Step 8a Choice mapping, naming the `fsi_status` Compose `Map_RunStatus`.
   Any unmapped label terminates before a scan-run row is created.
3. Add **Dataverse** > **List rows** for `fsi_caiscanrun`. Filter on
   `fsi_runid eq '<summary runId>'`, set **Row count** to `1`, and select only
   `fsi_caiscanrunid`.
4. Add a Condition:
   - If a row exists, set `ScanRunRowId` to
     `first(body('List_Scan_Run_By_RunId')?['value'])?['fsi_caiscanrunid']`.
   - If no row exists, add **Dataverse** > **Add a new row** with:
     - `fsi_name` and `fsi_runid` set to
       `body('Parse_Summary')?['summary']?['runId']`;
     - `fsi_startedat` set to `variables('RunStartedAt')`;
     - `fsi_status` set to `outputs('Map_RunStatus')`.
     Then set `ScanRunRowId` from the created row's `fsi_caiscanrunid`.
5. Add **Dataverse** > **Update a row** for `fsi_caiscanrun`. Set **Row ID** to
   `variables('ScanRunRowId')`.
6. Map the columns below. All names are Dataverse **logical** names (lowercase, no
   underscores between words). Choice columns are converted label→integer in
   **Step 8a** (do not write raw label strings to Choice columns).

| Flow Expression | Dataverse Column (logical) | Type | Notes |
|----------------|----------------------------|------|-------|
| `body('Parse_Summary')?['summary']?['runId']` | `fsi_runid` | String | Collision-resistant run identity (alternate-key column) |
| `variables('RunStartedAt')` | `fsi_startedat` | DateTime | Run start captured at flow start (the scanner JSON carries no run timing) |
| `utcNow()` | `fsi_completedat` | DateTime | Completion timestamp at write time |
| `body('Parse_Summary')?['summary']?['status']` | `fsi_status` | Choice | Overall run status (Complete / Incomplete / Failed / Dry Run) — Step 8a |
| `body('Parse_Summary')?['summary']?['environmentEnumeration']?['status']` | `fsi_environmentenumerationstatus` | Choice | Layer 1 environment enumeration — **special** map Success→Full / Failed→Failed / Dry Run→Dry Run — Step 8a |
| `length(coalesce(body('Parse_Summary')?['summary']?['environmentFailures'], json('[]')))` | `fsi_environmentfailurecount` | Integer | Count of per-environment coverage failures |
| `body('Parse_Summary')?['summary']?['environmentEnumeration']?['httpStatus']` | `fsi_environmentenumerationhttpstatus` | Integer (nullable) | Enumeration HTTP status (null on success) |
| `body('Parse_Summary')?['summary']?['environmentEnumeration']?['reason']` | `fsi_environmentenumerationreason` | String (nullable) | Sanitized enumeration failure reason |
| `body('Parse_Summary')?['summary']?['coverageScope']?['layers']?['environmentDataverse']` | `fsi_dataverselayerstatus` | Choice | Layer 2 (per-environment Dataverse) status — Step 8a |
| `body('Parse_Summary')?['summary']?['environmentCount']` | `fsi_environmentcount` | Integer | Environments enumerated this run |
| `body('Parse_Summary')?['summary']?['environmentEnumeration']?['dataverseEnvironmentCount']` | `fsi_dataverseenvironmentcount` | Integer | Environments in Layer 2 scope, including malformed candidates that surface as coverage failures |
| `body('Parse_Summary')?['summary']?['environmentEnumeration']?['skippedNoDataverseCount']` | `fsi_nodataverseenvironmentcount` | Integer | Environments explicitly classified without Dataverse; Layer 2 not applicable |
| `body('Parse_Summary')?['summary']?['scannedAgentCount']` | `fsi_dataversescannedagentcount` | Integer | Agents scanned through the Dataverse layer |
| `body('Parse_Summary')?['summary']?['agent365']?['requestedMode']` | `fsi_agent365requestedmode` | Choice | Present / Absent / Auto — Step 8a |
| `body('Parse_Summary')?['summary']?['agent365']?['resolvedState']` | `fsi_agent365resolvedstate` | Choice | Present / Absent / NotDetected / Inconclusive — Step 8a |
| `body('Parse_Summary')?['summary']?['agent365']?['resolutionSource']` | `fsi_agent365resolutionsource` | String | Write **directly** — CLI / Environment / DeprecatedAlias / Default / LicenseProbe / DryRun (**no Switch**) |
| `body('Parse_Summary')?['summary']?['agent365']?['detectionConfidence']` | `fsi_agent365detectionconfidence` | Choice | OperatorDeclared / Confirmed / Heuristic / Inconclusive / NotApplicable — Step 8a |
| `body('Parse_Summary')?['summary']?['agent365']?['layerStatus']` | `fsi_agent365layerstatus` | Choice | Full / Deferred / Unsupported / Partial / Failed / Dry Run — Step 8a |
| `body('Parse_Summary')?['summary']?['agent365']?['licenseProbeAttempted']` | `fsi_licenseprobeattempted` | Boolean | Pass `true` / `false` directly (no Switch) |
| `body('Parse_Summary')?['summary']?['coverageScope']?['layers']?['packageApi']` | `fsi_packageapilayerstatus` | Choice | Layer 4 (Package API) coverage status — Step 8a |
| `body('Parse_Summary')?['summary']?['agent365']?['packageApiAttempted']` | `fsi_packageapiattempted` | Boolean | Pass `true` / `false` directly (no Switch) |
| `body('Parse_Summary')?['summary']?['agent365']?['httpStatus']` | `fsi_packageapihttpstatus` | Integer (nullable) | Package-API HTTP status |
| `body('Parse_Summary')?['summary']?['agent365']?['errorCode']` | `fsi_packageapierrorcode` | String (nullable) | Sanitized Package-API error code |
| `body('Parse_Summary')?['summary']?['agent365']?['reason']` | `fsi_packageapireason` | Memo (nullable) | Sanitized Agent 365 resolution or Package-API reason (no token material) |
| `body('Parse_Summary')?['summary']?['agent365']?['packagesObserved']` | `fsi_packagecount` | Integer (**nullable**) | **Map the raw value.** `null` = not observed (deferred / not attempted); `0` = observed empty. Do **not** coalesce to `0`. |
| `body('Parse_Summary')?['summary']?['agent365']?['packageNewRowCount']` | `fsi_packagenewrowcount` | Integer (**nullable**) | Same null-vs-zero rule as above |
| `body('Parse_Summary')?['summary']?['agent365']?['pagingTruncated']` | `fsi_packagescantruncated` | Boolean | Pass `true` / `false` directly |
| `body('Parse_Summary')?['summary']?['coverageScope']?['layers']?['arg']` | `fsi_arglayerstatus` | Choice | Layer 1 (ARG) coverage status — Step 8a |
| `body('Parse_Summary')?['summary']?['argAgentCount']` | `fsi_argagentcount` | Integer | Agents discovered through the ARG layer |
| `body('Parse_Summary')?['summary']?['argLayer']?['httpStatus']` | `fsi_arghttpstatus` | Integer (nullable) | ARG query HTTP status |
| `body('Parse_Summary')?['summary']?['coreAgentCount']` | `fsi_coreagentcount` | Integer | Total agent rows emitted to the canonical agent table, including package-only rows |
| `body('Parse_Summary')?['summary']?['featureCount']` | `fsi_featurecount` | Integer | Feature rows written this run |
| `body('Parse_Summary')?['summary']?['authShareCount']` | `fsi_authsharecount` | Integer | Auth/share rows recorded this run |
| `body('Parse_Summary')?['summary']?['coverageScope']?['layers']?['registry']` | `fsi_registrylayerstatus` | Choice | Registry-correlation coverage status — Step 8a |
| `body('Parse_Summary')?['summary']?['registryCorrelation']?['registryRowCount']` | `fsi_registryrowcount` | Integer (nullable) | Registry export rows read (`null` when `--registry-export` not supplied) |
| `body('Parse_Summary')?['summary']?['registryCorrelation']?['matched']` | `fsi_registrymatchedcount` | Integer (nullable) | Registry rows matched to agents |
| `body('Parse_Summary')?['summary']?['registryCorrelation']?['unmatchedRegistryRows']` | `fsi_registryunmatchedcount` | Integer (nullable) | Registry rows with no agent match |
| `body('Parse_Summary')?['summary']?['registryCorrelation']?['ambiguousNameSkipped']` | `fsi_registryambiguousnameskippedcount` | Integer (nullable) | Ambiguous-name rows skipped |
| `body('Parse_Summary')?['summary']?['registryCorrelation']?['invalidDateWarnings']` | `fsi_registryinvaliddatewarningcount` | Integer (nullable) | Invalid as-of date warnings |
| `body('Parse_Summary')?['summary']?['coverageScope']?['layers']?['entitlement']` | `fsi_entitlementlayerstatus` | Choice | Entitlement-resolution coverage status — Step 8a |
| `body('Parse_Summary')?['summary']?['entitlementResolution']?['ownersConsidered']` | `fsi_entitlementownersconsideredcount` | Integer (nullable) | Owners considered for entitlement resolution |
| `body('Parse_Summary')?['summary']?['entitlementResolution']?['paidCount']` | `fsi_entitlementpaidcount` | Integer (nullable) | Owners resolved to a paid Copilot entitlement |
| `body('Parse_Summary')?['summary']?['entitlementResolution']?['chatOnlyCount']` | `fsi_entitlementchatonlycount` | Integer (nullable) | Owners resolved to Copilot Chat only |
| `body('Parse_Summary')?['summary']?['entitlementResolution']?['unknownCount']` | `fsi_entitlementunknowncount` | Integer (nullable) | Owners with unknown entitlement |
| `string(body('Parse_Summary')?['summary']?['coverageScope'])` | `fsi_coveragescopejson` | Memo | Full `coverageScope` JSON (audit evidence) |
| `string(body('Parse_Summary')?['summary'])` | `fsi_summaryjson` | Memo | Full `summary` JSON (audit evidence) |

> **Null vs zero (restated where it matters most).** For `fsi_packagecount`
> and `fsi_packagenewrowcount`, bind the scanner value **directly**. When the
> Package API was not attempted (for example `absent` / `Deferred`), the scanner
> emits `null` and the column must stay `null` — a deferred layer is *not* a zero
> catalog. Only an attempted Package API that returned an empty catalog writes
> `0`. `summary.packageNewRowCount` / `summary.packageScanTruncated` remain
> **deprecated top-level mirrors**, populated only when the Package API is
> attempted; prefer the `summary.agent365.*` fields.

7. Configure **Run after**: `Validate_Agent_Persistence` — set to **Succeeded**.
8. Rename the GUID update action: `Write_Scan_Run`.

> **Do not paste expression text into a plain field.** In the new designer,
> open the **Expression** editor and enter the formula without a leading `@`.
> Confirm the field renders one expression token such as `body(...)`,
> `outputs(...)`, or `length(...)`, not visible `@body(...)` text. Flow Checker
> can report zero errors for literal text that later fails Dataverse type
> conversion. If the editor rejects a chained nested path, the equivalent
> single-path form
> `outputs('Parse_Summary')?['body/summary/environmentEnumeration/dataverseEnvironmentCount']`
> is valid.

#### Step 8a — Label-to-Integer Conversion for `fsi_caiscanrun` Choice Fields

`fsi_caiscanrun` introduces **Choice columns** in v0.4. As in Step 7a, the scanner
emits **label strings** and Dataverse requires **option-set integers**, so add one
fail-visible **Compose** per Choice column below. `fsi_agent365resolutionsource` is
**not** in this list — it is a plain **String** column written **directly** from
`summary.agent365.resolutionSource` (one of `CLI` / `Environment` /
`DeprecatedAlias` / `Default` / `LicenseProbe` / `DryRun`) with **no** conversion.
Complete these mappings before the Step 8 lookup/create sequence. Use the same
Step 7a Compose pattern: `json('null')` for an empty nullable source, the listed
integer for a known label, and `-1` for an unknown non-empty label. `fsi_status`
is required, so its Compose returns `-1` for null or any value outside its four
listed labels. Name that Compose `Map_RunStatus` because the create, update, and
read-back actions reuse its output. Terminate before List rows if any mapping
Compose returns `-1`.

> **Option-set integers (locked in the v0.4 schema).** The values below are the
> **canonical** option-set integers for the `fsi_caiscanrun` Choice columns — map
> each known label to the exact integer shown. The shared **layer-status**
> option set applies to `fsi_agent365layerstatus`, `fsi_arglayerstatus`,
> `fsi_packageapilayerstatus`, `fsi_registrylayerstatus`,
> `fsi_entitlementlayerstatus`, and `fsi_dataverselayerstatus`.
> `fsi_environmentenumerationstatus` **also** stores a layer-status integer but
> maps from a **different source vocabulary** (see its dedicated table below).

**`fsi_status`** — overall run status:

| Label | Integer |
|-------|---------|
| `Complete` | `100000000` |
| `Incomplete` | `100000001` |
| `Failed` | `100000002` |
| `Dry Run` | `100000003` |

**`fsi_agent365requestedmode`** — the scanner emits title-case (`Present` /
`Absent` / `Auto`); the `--agent365` CLI flag itself stays lower-case:

| Scanner label | Integer |
|---------------|---------|
| `Present` | `100000000` |
| `Absent` | `100000001` |
| `Auto` | `100000002` |

**`fsi_agent365resolvedstate`**:

| Label | Integer |
|-------|---------|
| `Present` | `100000000` |
| `Absent` | `100000001` |
| `NotDetected` | `100000002` |
| `Inconclusive` | `100000003` |

**`fsi_agent365detectionconfidence`**:

| Label | Integer |
|-------|---------|
| `OperatorDeclared` | `100000000` |
| `Confirmed` | `100000001` |
| `Heuristic` | `100000002` |
| `Inconclusive` | `100000003` |
| `NotApplicable` | `100000004` |

**`fsi_agent365layerstatus`**, **`fsi_arglayerstatus`**,
**`fsi_packageapilayerstatus`**, **`fsi_registrylayerstatus`**,
**`fsi_entitlementlayerstatus`**, and **`fsi_dataverselayerstatus`** — shared
**layer-status** option set (source labels come from `summary.agent365.layerStatus`
and `summary.coverageScope.layers.*`):

| Label | Integer |
|-------|---------|
| `Full` | `100000000` |
| `Deferred` | `100000001` |
| `Unsupported` | `100000002` |
| `Partial` | `100000003` |
| `Failed` | `100000004` |
| `Dry Run` | `100000005` |

**`fsi_environmentenumerationstatus`** — **special mapping.** Its source
(`summary.environmentEnumeration.status`) uses `Success` / `Failed` / `Dry Run`,
**not** the layer-status vocabulary. Map the three source labels into the shared
layer-status integers:

| Source label (`environmentEnumeration.status`) | Stored layer-status | Integer |
|------------------------------------------------|---------------------|---------|
| `Success` | `Full` | `100000000` |
| `Failed` | `Failed` | `100000004` |
| `Dry Run` | `Dry Run` | `100000005` |

> **Fail visibly.** If any run-level mapping Compose returns `-1`, append the
> column and offending label to `UnmappedRows`, send a sanitized notification,
> and terminate with status **Failed** before creating the run row. Extend the mapping using
> [dataverse-schema.md](dataverse-schema.md) before re-running.

#### Step 8b — Read-back and idempotency verification

After `Write_Scan_Run`, confirm the single ledger row persisted:

1. Add action: **Dataverse** > **Get a row by ID**, table `fsi_caiscanrun`,
   using `variables('ScanRunRowId')` as the primary Row ID.
2. Add a **Condition** that all critical fields equal the parsed payload:
   - `fsi_runid` equals `summary.runId`;
   - `fsi_status` equals `outputs('Map_RunStatus')`;
   - `fsi_coreagentcount` equals `summary.coreAgentCount`;
   - `fsi_dataverseenvironmentcount` equals
     `summary.environmentEnumeration.dataverseEnvironmentCount`;
   - `fsi_dataversescannedagentcount` equals `summary.scannedAgentCount`;
   - `fsi_environmentfailurecount` equals the length of
     `summary.environmentFailures`;
   - `fsi_nodataverseenvironmentcount` equals
     `summary.environmentEnumeration.skippedNoDataverseCount`;
   - `fsi_packageapiattempted` equals
     `summary.agent365.packageApiAttempted`;
   - `fsi_packagecount` equals `summary.agent365.packagesObserved`, preserving
     null versus zero.
   If any comparison fails, use the false branch to send a sanitized
   verification-failure notification and then **Terminate** the flow as Failed.
   A technical Get-row failure is caught by the Scope failure path in Step 9.
3. Rename actions: `ReadBack_Scan_Run` and `Verify_Scan_Run`.

> **Exactly one row per run.** The lookup/create/GUID-update sequence reuses the
> same row for a repeated `runId`, while the active `fsi_ScanRunKey` uniqueness
> constraint blocks duplicate ledger rows. Configure the trigger for one active
> run because lookup and create are separate connector calls. A distinct,
> collision-resistant `runId` per scheduled run supports a separate ledger row
> for each run while agent rows join back via `fsi_runid`.

### Step 9: Notify on Persistence Failures and Coverage Gaps

The persistence-failure path is required. The normal coverage-gap notification
is optional.

1. Add a Scope named `Persistence_Failure_Notification` after
   `Persist_And_Verify_Scan_Run`. Configure **Run after** for **Failed**,
   **Timed out**, and **Skipped**. Send a sanitized persistence-failure
   notification from this Scope using action names/statuses rather than raw
   connector response bodies, then terminate the flow as Failed.
2. Add the normal coverage **Condition** after
   `Persist_And_Verify_Scan_Run`, configured for **Succeeded** only.
3. Condition — fire when the scan is not cleanly complete, a **requested** layer
   failed, **or** a reconciliation gap exists:
   - `body('Parse_Summary')?['summary']?['status']` is **not equal to** `Complete`
   - **or** `length(body('Parse_Summary')?['summary']?['environmentFailures'])` is greater than `0`
   - **or** `body('Parse_Summary')?['summary']?['agent365']?['layerStatus']` is **equal to** `Partial`
   - **or** `body('Parse_Summary')?['summary']?['agent365']?['layerStatus']` is **equal to** `Failed`
   - **or** `body('Parse_Summary')?['summary']?['agent365']?['layerStatus']` is **equal to** `Unsupported`
   - **or** `body('Parse_Summary')?['summary']?['agent365']?['resolvedState']` is **equal to** `Inconclusive`
   - **or** `length(body('Parse_Summary')?['summary']?['reconciliation']?['in_arg_only'])` is greater than `0`
   - **or** `length(body('Parse_Summary')?['summary']?['reconciliation']?['in_dataverse_only'])` is greater than `0`.
4. In the **Yes** branch, add **Microsoft Teams** > **Post adaptive card in a
   chat or channel** (or **Send an email**) summarizing the gap. Include the
   overall `summary.status`, `summary.environmentEnumeration.status`, the
   `summary.environmentFailures[]` records (environment id, stage, HTTP status),
   the `summary.agent365` block (`resolvedState`, `layerStatus`, sanitized
   `errorCode` / `reason`), and the reconciliation deltas (agents in ARG but not
   scanned, and vice versa). Coverage gaps are surfaced for review, not silently
   dropped — an `Incomplete` or `Failed` status, any environment failure, or a
   `Partial` / `Failed` / `Unsupported` requested layer means the inventory is a
   partial picture and must not be treated as a clean, agent-free result.
5. Rename: `Check_Coverage_And_Reconciliation_Gap`.

> **Deferred / NotDetected are informational, not alerts.** Do **not** raise a
> failure notification when `summary.agent365.layerStatus` is `Deferred` or when
> `resolvedState` is a heuristic `NotDetected` — these are expected outcomes of
> the operator's declared scope (for example the default `absent` mode). They do
> **not** degrade `summary.status`. Report them as **informational context only**,
> and **never** render a `Deferred` Layer 4 as "zero Agent Builder agents" — those
> agents may still be present even when authoring-surface classification is
> unavailable. **`Unsupported` is different:** it is
> an *attempted* layer the platform could not satisfy (a coverage failure), so it
> **degrades the run and alerts** exactly like `Partial` / `Failed`. Alert on
> `Partial` / `Failed` / `Unsupported` requested-layer outcomes, an `Inconclusive`
> resolution, or an overall `Incomplete` / `Failed` run.

> **Enumeration failure is a run failure.** When
> `summary.environmentEnumeration.status` is `Failed`, the environment list itself
> could not be read (for example a 401/403). The scanner also exits non-zero in
> this case, so the Azure Automation job reports **Failed** and `Scope_Catch`
> (Step 10) additionally fires. Do not interpret a zero-environment /
> zero-agent result from a failed enumeration as an empty tenant.

### Step 10: Error Handling (Scope_Catch)

1. Wrap steps 3–9 in a **Scope** named `Scope_Main`.
2. Add a parallel **Scope** named `Scope_Catch`.
3. Configure `Scope_Catch` to run after `Scope_Main` has **Failed** or
   **Timed Out**.
4. Inside `Scope_Catch`, add **Send an email (V2)** to the governance team with
   the error details from `Scope_Main`.

---

## Troubleshooting

### Azure Automation Job Failures

- **Job stuck in "Running"**: check the Automation job logs; the job may be
  waiting on a module or Python package install.
- **Job completes but summary is empty**: verify the scanner ran with valid
  credentials (`--auth-mode managed-identity`) and that the managed identity has the required scopes.
- **Authentication errors**: confirm the managed identity has consent for the
  Power Platform API, BAP, and per-environment Dataverse scopes.

### ARG Returns No Agents (Layer 1)

- Confirm the type resolves:
  `az graph query -q "PowerPlatformResources | where type == 'microsoft.copilotstudio/agents'"`.
- Remember the data lives in `PowerPlatformResources`, **not** the standard
  `resources` table — querying `resources` returns nothing for this type.
- If conditional access enforces ARM MFA, allow the PPAC client ID
  `00b46ad5-e4ae-43ac-a878-281fc03d0839` and "Microsoft Azure Management".

### Dataverse Write Failures

The **flow-writer** identity (the flow's Dataverse connection) is the only identity
that writes the CAI tables; the read-only scanner never writes Dataverse.

| Error Code | Cause | Resolution |
|-----------|-------|------------|
| 403 Forbidden | Flow-writer identity lacks Create/Write on CAI tables | Assign the flow's Dataverse connection a role with Organization-level Create on the CAI tables in the governance environment |
| 404 Not Found | Table not deployed | Deploy the schema (`scripts/create_cai_dataverse_schema.py`) |
| 400 Bad Request | Column-name mismatch | Verify logical column names against `dataverse-schema.md` |

### Scan Reports `Incomplete` / `Failed` or Environment Failures

The scanner now surfaces coverage gaps instead of returning a success-shaped empty
result. Use the summary signals to diagnose:

- **`summary.environmentEnumeration.status == "Failed"`** — the environment list
  itself could not be read (often 401/403). Confirm the scanner service principal
  is registered as a **Power Platform management application** and has ARM access.
  Zero environments here is a failure, **not** an empty tenant.
- **An environment in `summary.environmentFailures[]` with `stage: "bots"` and
  `httpStatus: 403`** — the scanner service principal is missing (or lacks the
  read-only role) as an **application user** in that environment. Add the read-only
  application user for `bot` / `botcomponent` and re-run. This is the coverage
  **stop condition** from [prerequisites.md](prerequisites.md#scanner-environment-coverage-verification-and-stop-condition).
- **`stage: "botcomponents"` failures** — the bot was discovered but its feature
  read failed; the agent is retained and flagged `Incomplete Scan`.
- **`summary.argLayer.status == "Failed"`** — a Layer 1 ARG query failure (distinct
  from `Available` with `agentCount: 0`). Layer 2 remains the load-bearing default;
  reconciliation is degraded until ARG succeeds.

### `botcomponent` Query Returns 400 (Layer 2)

- The `botcomponent` → `bot` lookup is `parentbotid` (`_parentbotid_value`), not
  `_botid_value`. Filtering on `_botid_value` returns `400 Bad Request`.

---

*Copilot Agent Inventory — Flow Setup Guide v0.4.0-preview*
