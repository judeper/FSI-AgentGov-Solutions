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
> this flow converts each label to its Dataverse option-set integer via Switch /
> Compose actions before writing (see Step 7a below). This flow reads the scanner
> JSON output, iterates over `agents[]` to upsert each record into
> `fsi_copilotagent` (including all new package, owner, and entitlement fields),
> and writes the run summary. All Dataverse persistence is the responsibility
> of this flow.

## Prerequisites

Before creating the flow, confirm you have:

- [ ] **Azure Automation Account** (or an Azure Function / hosted runner) with:
  - The discovery scanner (`scripts/discover_agents.py`) deployed as a runnable
    job, running under a **managed identity** (system- or user-assigned).
  - Python 3.9+ and the packages in `scripts/requirements.txt` available to the
    job.
- [ ] **Dataverse environment** with the CAI schema deployed:
  - 8 tables: `fsi_copilotagent`, `fsi_caienvironment`, `fsi_caiagentfeature`,
    `fsi_caiauthshare`, `fsi_caibillingentitlement`, `fsi_caiusagesignal`,
    `fsi_caiworkiqstate`, `fsi_caicompliancestate`.
- [ ] **Scanner service principal** with the roles and scopes in
  [prerequisites.md](prerequisites.md) (environment enumeration + per-environment
  `bot` / `botcomponent` read + CAI table write).
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
| `GovernanceDataverseUrl` | String | `https://governance.crm.dynamics.com` | Dataverse environment hosting the CAI tables |
| `TenantId` | String | `{{TENANT_DOMAIN}}` | Microsoft Entra ID tenant identifier |
| `SubscriptionId` | String | `{{AZURE_SUBSCRIPTION}}` | Azure subscription containing the Automation Account |
| `ResourceGroup` | String | `{{RESOURCE_GROUP}}` | Resource group with the Automation Account |
| `AutomationAccount` | String | `{{AUTOMATION_ACCOUNT}}` | Azure Automation Account name |
| `TeamsGroupId` | String | `{{TEAMS_GROUP_ID}}` | Teams group ID for run notifications (optional) |
| `TeamsChannelId` | String | `{{TEAMS_CHANNEL_ID}}` | Teams channel ID for run notifications (optional) |

> **Integrated scanner additional variables** (add when using `--registry-export`):
> `RegistryExportPath` (String — path to the XLSX or CSV registry export),
> `ColumnMapPath` (String — default `templates/registry-columnmap.sample.json`),
> `AsOfDateTime` (String — ISO-8601 UTC as-of timestamp for the export, e.g.
> `2026-07-20T18:00:00Z`).

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
       --enable-package-api \
       --registry-export <RegistryExportPath> \
       --columnmap <ColumnMapPath> \
       --as-of <AsOfDateTime> \
       --resolve-entitlement \
       --output scan.json
     ```
     Omit `--registry-export` (and related flags) to run three-layer discovery
     only; the output is backward-compatible when these flags are absent.
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
                "argAgentCount": { "type": "integer" },
                "scannedAgentCount": { "type": "integer" },
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

### Step 7: Persist Agent Records to Dataverse

The scanner emits each discovered agent as an object in `agents[]`. Use an
**Apply to each** action to upsert every agent row into `fsi_copilotagent`.

1. Add action: **Control** > **Apply to each**.
2. Select output: expression `body('Parse_Summary')?['agents']` (the top-level
   `agents` array from the full scanner output; `agents` is **not** nested inside `summary`).
3. Inside the loop, add a **Condition** action to select the correct
   alternate key using the following deterministic precedence:

   * **Branch A — environment-scoped rows (PRIMARY)** — condition:
     `and(not(empty(items('Apply_to_each')?['fsi_agentid'])), not(empty(items('Apply_to_each')?['fsi_environmentid'])))` evaluates to `true`:
     add action **Dataverse** > **Update a row** and select the
     **fsi_AgentEnvKey** alternate key. Supply **both** `fsi_agentid` **and**
     `fsi_environmentid`; omitting either column causes the upsert to fail
     because fsi_AgentEnvKey is a composite key requiring both components.
     This branch covers both pre-existing ARG/Dataverse rows and
     package-enriched versions of those rows, helping prevent transition
     duplicates when Package API enrichment begins on an existing tenant.

   * **Branch B — package-only rows (FALLBACK)** — `else if`
     `not(empty(items('Apply_to_each')?['fsi_packageid']))` evaluates to `true`:
     add action **Dataverse** > **Update a row** and select the
     **fsi_PackageKey** alternate key. Supply only `fsi_packageid` as the
     key column. Do **not** supply `fsi_environmentid`; package-only rows
     (where `fsi_agentid` equals `fsi_packageid`) have no environment scope,
     and including an empty value causes the key lookup to fail.

   * **Branch C — unpersistable rows (ERROR)** — when neither condition is
     true, add a **Terminate** action (status: Failed) or append the row to
     an error collection variable for post-run review. Do **not** add a
     generic **Add a new row** action without an idempotency key; doing so
     accumulates unkeyed duplicate rows on every scheduled run.

   > **Note:** A newly created alternate key (fsi_PackageKey) must reach
   > Active status in Dataverse before scheduled upserts begin.

   This deterministic precedence helps prevent transition duplicates (existing
   rows whose `fsi_packageid` is subsequently populated) and package-only
   duplicates (rows lacking `fsi_environmentid`) from accumulating across
   scheduled runs.

4. Table: `fsi_copilotagent`.
5. Map the columns below. Use `items('Apply_to_each')` to reference the current
   agent object. All column names are Dataverse **logical** names (lowercase, no
   underscores between words).

| Flow Expression | Dataverse Column (logical) | Type | Notes |
|----------------|----------------------------|------|-------|
| `items('Apply_to_each')?['fsi_agentid']` | `fsi_agentid` | String | PRIMARY key component of fsi_AgentEnvKey; required together with fsi_environmentid (Branch A — checked first) |
| `items('Apply_to_each')?['fsi_environmentid']` | `fsi_environmentid` | String | PRIMARY key component of fsi_AgentEnvKey; present for environment-scoped and package-enriched rows (Branch A); absent for package-only rows (Branch B) |
| `items('Apply_to_each')?['fsi_agentname']` | `fsi_agentname` | String | Display name |
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
| `items('Apply_to_each')?['fsi_scancompleteness']` | `fsi_scancompleteness` | Picklist | Complete / Incomplete Scan / Failed |

> **Column naming:** always use Dataverse **logical** names (lowercase, no
> underscores between words) in flow column mappings — for example
> `fsi_agentid`, `fsi_ownerupn`, `fsi_packagetype`. See
> [dataverse-schema.md](dataverse-schema.md) for the authoritative list.

6. Configure **Run after**: `Parse_Summary` — set to **Succeeded**.
7. Rename action: `Persist_Agent_Records`.

#### Step 7a — Label-to-Integer Conversion for Choice Fields

Before the **Add a new row** action in the loop, add a **Switch** (or **Compose**)
action for each Choice column to convert the scanner's label string to the Dataverse
option-set integer. The scanner emits labels; Dataverse requires integers.
`fsi_isblocked` is a Two-Options (Boolean) field — pass `true` / `false` directly,
no Switch needed.

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
| `fsi_scancompleteness` | `Complete` | `100000000` |
| `fsi_scancompleteness` | `Incomplete Scan` | `100000001` |
| `fsi_scancompleteness` | `Failed` | `100000002` |

> **Implementation tip:** Add a **Switch** action before `Persist_Agent_Records`.
> Set the **On** value to the scanner label
> (e.g. `items('Apply_to_each')?['fsi_discoverysource']`). Each **Case** sets
> a variable to the corresponding integer. Reference that variable in the
> **Add a new row** column mapping instead of the raw label string.

---

### Step 8: Write the Run Summary Record to Dataverse

> **Why this runs before notification:** the run record is written regardless of
> whether notification succeeds, supporting compliance with the record-keeping
> expectations of FINRA Rule 4511 and SEC Rule 17a-3.

Map the parsed summary to your run-tracking table (for example an
`fsi_caienvironment` rollup row or a dedicated run table):

| Flow Expression | Dataverse Column (logical) | Type | Description |
|----------------|----------------------------|------|-------------|
| `body('Parse_Summary')?['summary']?['runId']` | `fsi_runid` | String | Unique run identifier |
| `body('Parse_Summary')?['summary']?['scannedAgentCount']` | `fsi_agentcount` | Integer | Agents recorded this run |
| `utcNow()` | `fsi_lastscannedat` | DateTime | Scan completion timestamp |
| `body('Parse_Summary')?['summary']?['registryCorrelation']?['registryRowCount']` | `fsi_registryrowcount` | Integer | Registry rows in the correlation export |
| `body('Parse_Summary')?['summary']?['registryCorrelation']?['matched']` | `fsi_registrymatched` | Integer | Registry rows matched to agents |
| `body('Parse_Summary')?['summary']?['registryCorrelation']?['status']` | `fsi_registrycorrelationstatus` | String | Complete / Incomplete / Failed |
| `body('Parse_Summary')?['summary']?['entitlementResolution']?['ownersConsidered']` | `fsi_entitlementownersconsidered` | Integer | Owner UPNs considered |
| `body('Parse_Summary')?['summary']?['entitlementResolution']?['paidCount']` | `fsi_entitlementpaidcount` | Integer | Paid Copilot owners |
| `body('Parse_Summary')?['summary']?['entitlementResolution']?['chatOnlyCount']` | `fsi_entitlementchatonlycount` | Integer | Copilot Chat Only owners |
| `body('Parse_Summary')?['summary']?['entitlementResolution']?['status']` | `fsi_entitlementresolutionstatus` | String | Complete / Incomplete / Failed |

Rename action: `Write_Run_Summary`.

### Step 9: Notify on Reconciliation Gaps (optional)

1. Add action: **Condition**.
2. Condition:
   `length(body('Parse_Summary')?['summary']?['reconciliation']?['in_arg_only'])` is greater than `0`
   **or** `length(body('Parse_Summary')?['summary']?['reconciliation']?['in_dataverse_only'])` is greater than `0`.
3. Configure **Run after**: `Write_Run_Summary` — set to run after **Succeeded**
   and **Failed** so notification proceeds even if the write fails.
4. In the **Yes** branch, add **Microsoft Teams** > **Post adaptive card in a
   chat or channel** (or **Send an email**) summarizing the reconciliation gap
   (agents in ARG but not scanned, and vice versa). Coverage gaps are surfaced
   for review, not silently dropped.
5. Rename: `Check_Reconciliation_Gap`.

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

| Error Code | Cause | Resolution |
|-----------|-------|------------|
| 403 Forbidden | Identity lacks Create/Write on CAI tables | Assign a role with Organization-level Create on the CAI tables |
| 404 Not Found | Table not deployed | Deploy the schema (`scripts/create_cai_dataverse_schema.py`) |
| 400 Bad Request | Column-name mismatch | Verify logical column names against `dataverse-schema.md` |

### `botcomponent` Query Returns 400 (Layer 2)

- The `botcomponent` → `bot` lookup is `parentbotid` (`_parentbotid_value`), not
  `_botid_value`. Filtering on `_botid_value` returns `400 Bad Request`.

---

*Copilot Agent Inventory — Flow Setup Guide v0.3.0-preview*
