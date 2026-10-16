# Flow Configuration

Power Automate flow setup for Copilot Billing Governance (CBG). This solution ships
**documentation only** — build the flows manually in the Power Automate designer. No
exported flow JSON is included.

> **2026-10-16 verification gate:** these are preview design instructions, not a
> validated unattended integration. Graph `licenseDetails` is delegated-only; do
> not substitute a managed-identity token for the license-read step. Microsoft
> 365 Chat/SharePoint billing policies do not establish Work IQ API spending-policy
> coverage. Keep the analyzer monitor-only until each source and coverage boundary
> is validated. See [prerequisites](prerequisites.md) and
> [current verification findings](../README.md#technical-verification).

---

## Overview

CBG uses two Power Automate flows:

| Flow | Purpose | Trigger |
|------|---------|---------|
| **CBG-PolicySync** | Reconcile PAYG + credit policy state and snapshot tenant policy counts | Scheduled (every 15 minutes) |
| **CBG-CoverageGapAnalyzer** | Classify pathway, evaluate entitlement, materialize decisions, aggregate per-agent coverage gaps | Scheduled (nightly) |

```
┌─────────────────────────┐  every 15 min   ┌──────────────────────────────┐
│   CBG-PolicySync        │────────────────▶│ fsi_cbgbillingpolicy (PAYG)  │
│   (read 2 policy objects)│                 │ fsi_cbgcreditpolicy (Credit) │
└─────────────────────────┘                 └──────────────────────────────┘

┌─────────────────────────┐  nightly        ┌──────────────────────────────┐
│ CBG-CoverageGapAnalyzer │────────────────▶│ fsi_cbgentitlementmaterialized│
│ classify → evaluate →   │   materialize    │   (per agent × user, ttl)     │
│ materialize → aggregate │────────────────▶│ fsi_cbgcoveragegap            │
└─────────────────────────┘   aggregate      │   (per agent, monitor-only)   │
                                             └──────────────────────────────┘
```

---

## Connection references

Configure these before building the flows.

| Connection reference | Connector | Purpose |
|---------------------|-----------|---------|
| `fsi_cr_dataverse` | Dataverse | Read/write CBG tables |
| `fsi_cr_http_azuread` | HTTP with Microsoft Entra ID | Read billing/credit policy and license/group state via Graph and admin APIs |
| `fsi_cr_teams` | Microsoft Teams | Post coverage-gap summaries to a governance channel |

> Prefer a managed identity for the scheduled host. The `fsi_cr_http_azuread`
> connection is a fallback for environments where a flow cannot use a managed
> identity directly.

---

## Environment variables

| Variable | Description | Example |
|----------|-------------|---------|
| `fsi_CBG_TenantId` | Microsoft Entra ID tenant ID | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `fsi_CBG_DataverseEnvironment` | Dataverse environment URL | `https://contoso.crm.dynamics.com` |
| `fsi_CBG_AzureSubscriptionId` | Azure subscription backing the PAYG policy | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `fsi_CBG_CreditScopeGroupId` | Entra group object ID for the credit scope | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` |
| `fsi_CBG_CoverageGapSampleCap` | Max blocked UPNs sampled per agent row | `20` |
| `fsi_CBG_GroupSizeThresholdT` | Audience size above which large groups are partitioned | `500` |
| `fsi_CBG_CacheTtlMinutes` | TTL for materialized entitlement decisions | `1440` (minutes) |
| `fsi_CBG_TeamsChannelId` | Teams channel for coverage-gap summaries | `19:xxxxx@thread.tacv2` |
| `fsi_CBG_ClientId` | Legacy dev-only Entra app client ID for local fallback | `xxxxxxxx-...` |

> **Security:** `fsi_CBG_ClientId` and any associated secret are a legacy dev-only
> fallback. Use managed identity for Azure-hosted production automation.

---

## Flow configuration

### CBG-PolicySync

**Purpose:** Reconcile the two policy objects and snapshot tenant policy counts so the
50 (PAYG) / 10 (credit) ceilings can be tracked.

| Setting | Default | Description |
|---------|---------|-------------|
| Recurrence | 15 minutes | How often to reconcile policy state |
| Pagination limit | 50 iterations | Max policy pages fetched per run |

**Steps (designer build):**

1. **Recurrence** trigger (15 minutes).
2. **Read PAYG policies** — use a validated policy read or an operator-supplied
   normalized snapshot reconciled against **Copilot > Billing & usage >
   Pay-as-you-go services**. Confirm scope and connection to the intended service;
   a summary list or HTTP 200 alone is insufficient. For each, upsert a
   `fsi_cbgbillingpolicy` row (set `fsi_azuresubscriptionid`, `fsi_isconnected`,
   `fsi_budgetalertthreshold`, `fsi_spendscope`, `fsi_lastsyncedat`).
3. **Read credit policies** — do not assume a public credit-policy API is available
   or that the PAYG list includes credit-policy scope. Use a validated read or
   an operator-verified snapshot, recording observation time and source evidence.
   Confirm prepaid allocation to the **Microsoft Copilot Chat** environment in
   **Licensing > Copilot Studio**, plus tenant-pool/PAYG overage settings. For each, upsert a
   `fsi_cbgcreditpolicy` row (set `fsi_prepaidcreditpack`, `fsi_creditsconsumed`,
   `fsi_hardstopenabled`, `fsi_surfacescope`, `fsi_assignedgroupid`,
   `fsi_lastsyncedat`).
4. **Snapshot counts** — set `fsi_policycountsnapshot` on each row to the observed
   tenant total (the column `MaxValue` is 50 for PAYG and 10 for credit; a snapshot at
   or above the ceiling indicates no headroom for additional policies).

> **Integration caveat:** CBG has no validated credit-policy/cap write integration;
> treat enforcement as **detect-and-alert**. Native agent caps do exist in
> **Licensing > Copilot Studio > Summary > Manage Agents**, with notifications
> and delayed hard stops; they do not stop separately billed agent flows.
> Source: [capacity and agent limits](https://learn.microsoft.com/power-platform/admin/manage-copilot-studio-messages-capacity).
> Work IQ API requires separate policies in **Copilot > Cost management**, outside
> this flow's two-object model.

### CBG-CoverageGapAnalyzer

**Purpose:** Produce the per-agent coverage-gap aggregate (monitor-only) and refresh
the materialized entitlement cache.

| Setting | Default | Description |
|---------|---------|-------------|
| Recurrence | Nightly | Coverage-gap analysis cadence |
| Sample cap | `fsi_CBG_CoverageGapSampleCap` | Blocked UPNs sampled per agent |
| Group-size threshold T | `fsi_CBG_GroupSizeThresholdT` | Partition large audiences above T |

**Steps (designer build):**

1. **Recurrence** trigger (nightly).
2. **List agents** — read the agent inventory (from `copilot-agent-inventory` once
   available; otherwise a fixture list).
3. **Classify pathway** — for each agent, derive `fsi_pathway` from `createdIn`
   (Azure Resource Graph `PowerPlatformResources`) and `configuredTier` (Work IQ).
4. **Evaluate entitlement** — use delegated diagnostic license resolution or
   reviewed fixture inputs, not unattended app-only `licenseDetails`. Apply the
   shipped preview contract per intended user, preserving unresolved-user and
   policy-uncertainty evidence separately from evaluated users; do not equate engine
   decisions with verified Microsoft access requirements;
   upsert `fsi_cbgentitlementmaterialized` rows with `fsi_decision`,
   `fsi_decisionreason`, `fsi_ttlexpiresat` (= now + `fsi_CBG_CacheTtlMinutes`).
5. **Aggregate per agent** — upsert one `fsi_cbgcoveragegap` row per agent:
   `fsi_eligibleusers`, `fsi_blockeduserscount`, capped `fsi_blockedsampleupns`,
   dominant `fsi_blockreasonsummary`, `fsi_spendscope`, `fsi_groupsizepartition`,
   `fsi_monitoronly = Yes`, `fsi_retainuntil`.
6. **Notify** — post a Teams summary of the top coverage gaps to
   `fsi_CBG_TeamsChannelId`.

> **Monitor-only first:** this flow takes **no enforcement action**. It records gaps
> so administrators can right-size policies and groups before any spend control is
> turned on.

---

## Testing flows

### Test CBG-PolicySync

1. Configure at least one PAYG or credit policy.
2. Run the flow manually.
3. Confirm `fsi_cbgbillingpolicy` and/or `fsi_cbgcreditpolicy` rows are upserted with
   a recent `fsi_lastsyncedat`.
4. Reconcile each row to a dated admin-center observation: scope, connected
   Chat/SharePoint service, prepaid allocation, and overage source. Reject a
   summary-only or unparseable policy as coverage evidence.

### Test CBG-CoverageGapAnalyzer

1. Provide a small fixture agent list with at least one `metered` and one `none`
   pathway agent (see `templates/entitlement-decision.sample.json`).
2. Run the flow manually.
3. Confirm one `fsi_cbgcoveragegap` row per agent, with `fsi_monitoronly = Yes` and a
   bounded `fsi_blockedsampleupns` sample (see `templates/coverage-gap.sample.json`).
4. Record intended, resolved, and unresolved user counts and policy uncertainty;
   a row with zero blocked users does not prove full entitlement coverage.
5. Include negative checks for app-only license reads, Work IQ API consumers
   without verified spending-policy coverage, non-agent-triggered flows, and CUA
   operations. The current engine does not implement all these cases; record
   unsupported cases for manual review rather than claiming a successful gate.

The PowerShell skeletons `Get-BillingPolicyInventory.ps1` and
`Invoke-EntitlementEvaluation.ps1` reproduce the same logic for local validation
without building the flows.

---

*Copilot Billing Governance v0.1.0-preview*
