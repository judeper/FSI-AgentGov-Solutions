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
   - Runbook / job: the wrapper that invokes
     `python scripts/discover_agents.py --environment-url <GovernanceDataverseUrl>
     --tenant-id <TenantId> --auth-mode managed-identity`.
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
2. Content: `Get_Job_Output` output (the scanner's `summary` object).
3. Schema (matches `discover_agents.py` summary output):

```json
{
    "type": "object",
    "properties": {
        "runId": { "type": "string" },
        "argAgentCount": { "type": "integer" },
        "scannedAgentCount": { "type": "integer" },
        "featureCount": { "type": "integer" },
        "environmentCount": { "type": "integer" },
        "reconciliation": {
            "type": "object",
            "properties": {
                "in_arg_only": { "type": "array" },
                "in_dataverse_only": { "type": "array" },
                "in_both": { "type": "array" }
            }
        }
    }
}
```

4. Rename action: `Parse_Summary`.

### Step 7: Write the Run Record to Dataverse

> **Why this runs before notification:** the run record is written regardless of
> whether notification succeeds, supporting compliance with FINRA Rule 4511 and
> SEC Rule 17a-3 record-keeping requirements.

If the scanner already upserts agents and features directly to Dataverse via
`$batch` (the default), this step records a **scan-run summary** row. Map summary
fields to your run-tracking table (for example a `fsi_caienvironment` rollup row
or a dedicated run table if you add one):

| Flow Expression | Dataverse Column (logical) | Type | Description |
|----------------|----------------------------|------|-------------|
| `runId` | `fsi_runid` | String | Unique run identifier |
| `scannedAgentCount` | `fsi_agentcount` | Integer | Agents scanned this run |
| `utcNow()` | `fsi_lastscannedat` | DateTime | Scan completion timestamp |

Rename action: `Write_Run_Record`.

> **Column naming:** always use Dataverse **logical** names (lowercase, no
> underscores between words) in flow column mappings — for example `fsi_runid`,
> `fsi_lastscannedat`, `fsi_agentcount`. See
> [dataverse-schema.md](dataverse-schema.md) for the authoritative list.

### Step 8: Notify on Reconciliation Gaps (optional)

1. Add action: **Condition**.
2. Condition: `length(in_arg_only)` is greater than `0`
   **or** `length(in_dataverse_only)` is greater than `0`.
3. Configure **Run after**: `Write_Run_Record` — set to run after **Succeeded**
   and **Failed** so notification proceeds even if the write fails.
4. In the **Yes** branch, add **Microsoft Teams** > **Post adaptive card in a
   chat or channel** (or **Send an email**) summarizing the reconciliation gap
   (agents in ARG but not scanned, and vice versa). Coverage gaps are surfaced
   for review, not silently dropped.
5. Rename: `Check_Reconciliation_Gap`.

### Step 9: Error Handling (Scope_Catch)

1. Wrap steps 3–8 in a **Scope** named `Scope_Main`.
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
- **Job completes but summary is empty**: verify the scanner ran with a valid
  `--environment-url` and that the managed identity has the required scopes.
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

*Copilot Agent Inventory — Flow Setup Guide v0.1.0-preview*
