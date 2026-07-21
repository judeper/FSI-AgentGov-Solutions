# Architecture - Copilot Agent Inventory

> **Status:** `0.3.0-preview`. This document describes the intended architecture
> of the discovery scanner and the canonical Dataverse system-of-record. Several
> build-time facts are tagged for live verification (see
> [Assumptions and build-time verifications](#assumptions-and-build-time-verifications));
> the tags mirror the `phase1-VERIFICATION-DIGEST.md` build-truth notation
> (✅ verified / 🔎 unverified-live-check / ⚠️ conflicted).

## Purpose

Copilot Agent Inventory is the tier-1 **system-of-record** for the FSI Copilot
governance build. It discovers every Copilot Studio and Microsoft 365 Copilot
Agent Builder agent across the tenant and persists a normalized inventory to
Dataverse. Downstream governance solutions read this inventory rather than
re-scanning the platform. The inventory is required for control
[1.2 — Agent Registry and Integrated Apps Management](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.2-agent-registry-and-integrated-apps-management/)
and supports compliance with the record-keeping expectations of FINRA Rule 4511
and SEC Rule 17a-3/17a-4 (a complete agent inventory is a prerequisite for the
documentation those rules require).

## Four-Layer Discovery

No single API returns a complete, tenant-wide agent inventory, so discovery
composes four layers and reconciles them.

### Layer 1 — Tenant-wide discovery via Azure Resource Graph (ARG)

- Agents are projected into a dedicated ARG table, **`PowerPlatformResources`**
  (✅ verified) — **not** the standard `resources` table (querying `resources`
  returns nothing for this type). Resource type is
  **`microsoft.copilotstudio/agents`** (✅ verified).
- Query shape (✅ verified):
  `POST {PowerPlatformAPI}/resourcequery/resources/query?api-version=2024-10-01`
  with body `{ "TableName": "PowerPlatformResources", "Clauses": [...],
  "Options": { "Top": ..., "Skip": ..., "SkipToken": ... } }`. Paging uses
  `SkipToken`; responses carry `skipToken` / `totalRecords` / `resultTruncated`.
  The same data is also ARG-KQL queryable.
- Inventory GA was **March 31 2026** (✅ verified); several agent-specific fields
  (for example `isManaged`, `channels`, `authentication`, `capabilitiesCounts`,
  `powerPlatformConnectors[]`) remain in preview and must be re-pulled at build
  (🔎 unverified-live-check).
- There is **no ~500-agent ceiling** on the ARG/API path (that limit is a
  PPAC UI/search constraint only) (✅ verified). Data freshness is roughly
  15 minutes (≤20 minutes for agent-specific fields).
- The disambiguator field the entitlement classifier keys on is
  **`createdIn`** ∈ `"Copilot Studio"` | `"Microsoft 365 Copilot Agent Builder"`
  (✅ verified). Other GA fields used by the scanner: `name` (the Dataverse `bot`
  GUID), `properties.displayName`, `ownerId`, `environmentId`, `location`,
  `lastPublishedAt`, `schemaName`, and the identity triple
  `botId` / `entraAppId` / `entraAgentId`.
- **Live-confirm at build (🔎):** `microsoft.copilotstudio/agents` is absent from
  the standard ARG supported-types reference, so CLI/Explorer autocomplete may
  not list it. Confirm with
  `az graph query -q "PowerPlatformResources | where type == 'microsoft.copilotstudio/agents'"`
  at tenant scope before relying on Layer 1.

### Layer 2 — Per-environment Dataverse scan (`bot` + `botcomponent`)

For each environment returned by admin enumeration, the scanner queries the
environment's Dataverse instance for `bot` records and their `botcomponent`
children to enumerate agent features.

- **Lookup correction (✅ verified):** the `botcomponent` → `bot` parent is
  **`parentbotid` (`_parentbotid_value`)** via the `botcomponent_parent_bot`
  relationship — **not** `_botid_value`. Filtering on `_botid_value` returns
  `400 Bad Request`.
- **`componenttype` enum (✅ verified):** values run **0–19** (no codes ≥20 as of
  the 2025-10-31 reference). The brief's `{0,1,8,9–19}` shorthand **omits valid
  V1 codes 2–7** (Bot variable / Bot entity / Dialog / Trigger / Language
  understanding / Language generation); the scanner includes them.
- **V1 ↔ V2 pairing — match both codes (✅ verified):** Topic `{0,9}` ·
  Skill `{1,13}` · Bot entity `{3,11}` · Bot variable `{2,12}` ·
  Bot translations `{10}` (V2-only).
- **Six many-to-many relationships (✅ verified)**, intersect key
  `botcomponentid`: `botcomponent_aipluginoperation` (tools/plugins) ·
  `_connectionreference` · `_workflow` · `_environmentvariabledefinition` ·
  `_dvtablesearch` (Dataverse grounding) · `_msdyn_aimodel` (AI Builder).
- **`bot.generativeaiconfiguration` is NOT a real column (✅ verified)** —
  querying it 400s or returns null. Generative-AI / Work IQ configuration most
  plausibly lives in `botcomponent` rows of type **18 (Copilot Settings)**,
  **15 (Custom GPT)**, and/or **16 (Knowledge Source)**, or in `bot.configuration`
  (Memo, ~1 MB). This is **resolved by live sampling — the column is not assumed.**
- **JSON payload schema is undocumented (🔎):** `botcomponent.data` ("OBI format",
  ~1 MB) and `botcomponent.content` (opaque blob) have no documented key schema.
  The intended approach is to sample ~50 pilot agents (prioritizing types
  0/9, 15, 16, 17, 18 plus `bot.configuration`), derive parsers behind a schema
  registry keyed by `(componenttype, V1|V2)`, add golden-file parser tests, and
  **fail open with telemetry** on unrecognized keys rather than dropping the agent.
- **Build-time metadata refresh (🔎):** call
  `GET GlobalOptionSetDefinitions(Name='botcomponent_componenttype')` at build to
  catch any value ≥20 added since the (≈7-month-old) reference.

### Layer 3 — PPAC reconciliation

Power Platform admin center counts and environment lists are used as a
cross-check to reconcile Layer 1 against Layer 2 — surfacing agents present in
ARG but not in a Dataverse scan (and vice versa). Reconciliation output is
written to the inventory so coverage gaps are auditable rather than silent.

### Layer 4 — Package Management API (Agent Builder catalog, GA v1.0)

> **Activation:** requires `--enable-package-api` (off by default) and the
> `CopilotPackages.Read.All` application permission. See
> [prerequisites.md](prerequisites.md#package-management-api-layer-4-prerequisites).

- **Scope — Agent Builder only:** this layer queries packages filtered to
  `platform eq 'Microsoft 365 Copilot Agent Builder'` only. Copilot Studio
  agents are intentionally excluded: existing layers (ARG, per-environment
  Dataverse, and PPAC) already cover Copilot Studio agents, and package-to-bot
  joins are not strong enough to prevent duplicates.
- **Endpoint:** `GET https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages`
  with `$filter=platform eq 'Microsoft 365 Copilot Agent Builder'`. The
  `platform` field supports `$filter` with `eq`.
- **Auth:** application (app-only) permission `CopilotPackages.Read.All`
  (admin-consented). No signed-in user required for unattended automation.
- **Response envelope:** `{ "value": [ copilotPackage ] }`.
- **Fields captured per package:** `id` (`P_...`), `displayName`, `type`
  (`microsoft` / `external` / `shared` / `custom`), `platform`, `publisher`,
  `version`, `manifestId`, `manifestVersion`, `appId`, `availableTo`,
  `deployedTo`, `supportedHosts[]`, `elementTypes[]`
  (`Bots` / `DeclarativeAgent` / `CustomEngineAgent`), `isBlocked`.
  **No `owner`, `creator`, or `createdDate` field is returned by this API.**
- **Pagination:** `@odata.nextLink` is handled defensively. A truncated pull
  is recorded as an `Incomplete Scan` (GATE-1), never treated as a complete or
  silently empty result.
- **Reconciliation rule:** packages are joined to existing `fsi_copilotagent`
  rows (Agent Builder rows only — Copilot Studio rows are not enriched by this
  layer) via `appId` (Package.appId == `fsi_entraappid`) then `manifestId`. On
  a match the existing row is enriched in-place: `fsi_packageid`, package
  metadata columns, and `fsi_discoverysource = "Reconciled (multi-source)"` are
  set. On no match a **new** package-sourced row is created with
  `fsi_agentid = package_id` (`P_...`), `fsi_discoverysource = "Package
  Management API"`, and `fsi_ownermatchconfidence = "Unmatched"`.
- **Id-space isolation:** package `P_...` ids occupy a distinct space from
  Copilot Studio bot GUIDs. `reconcile_sources()` guards against cross-id-space
  false drift (see [Reconciliation limitation](#reconciliation-limitation) below).

## Scan Completeness

Lite / Agent Builder agents are recorded with
`fsi_caicompliancestate.fsi_scancompleteness = "Incomplete Scan"` when no
enriched definition is available. The Package Management API (Layer 4, GA v1.0,
application `CopilotPackages.Read.All`) returns package-level metadata
(`displayName`, `publisher`, `supportedHosts`, `appId`, `manifestId`, etc.)
for Agent Builder agents. An Agent Builder row that is enriched via Layer 4
carries more metadata than a Layer-1-only record; the scan completeness signal
may be upgraded from `Incomplete Scan` when the package layer produces a
successful match. Full feature enumeration (instructions, knowledge sources,
capabilities) remains unavailable via any public API for Agent Builder agents;
`fsi_caicompliancestate.fsi_scancompletenessreason` records the specific
gap.

## Package API — Owner Attribution and Entitlement

### Owner attribution (temporary bridge)

The Package Management API returns **no owner, creator, or creation-date
field**. Owner attribution for Agent Builder packages is sourced from a manual
Microsoft 365 admin center Agent Registry export (XLSX or CSV). This is a
**temporary bridge** until a live owner API is available.

Key limitations of this approach:

| Signal | Column | Limitation |
|--------|--------|-----------|
| Owner UPN / ID | `fsi_ownerupn`, `fsi_ownerid` | Derived from point-in-time manual export; may be stale |
| Owner as-of date | `fsi_ownerasofdatetime` | Timestamp of the export file, not a live lookup |
| Owner source | `fsi_ownersource` | Value `"Agent Registry Export"` (100000001) — a temporary bridge |
| Match confidence | `fsi_ownermatchconfidence` | `"Exact"` / `"Heuristic"` / `"Unmatched"` based on join quality |

Treat any `fsi_ownersource = "Agent Registry Export"` row as an approximation
and check `fsi_ownerasofdatetime` to assess staleness. Rows with
`fsi_ownermatchconfidence = "Unmatched"` have no owner attribution; their
`fsi_ownerentitlement` is `"Unknown"`.

### Entitlement classification

Owner entitlement is classified into three values via service-plan GUID lookup
against the owner's Microsoft 365 license (delegated to
`copilot-billing-governance/scripts/Get-CopilotEntitlement.ps1` — the GUID
allowlist is not duplicated into CAI):

| Value | Dataverse option | Meaning |
|-------|-----------------|---------|
| `Paid Copilot` | 100000000 | Owner holds a `M365_COPILOT_*` service plan |
| `Copilot Chat Only` | 100000001 | Owner has Bing Chat Enterprise (deny plan) but no paid plan |
| `Unknown` | 100000002 | Unresolved owner, lookup failure, or subprocess error |

`fsi_ownerentitlementevidence` stores matched service-plan GUIDs as a raw JSON
array. **SKU GUIDs (tenant-level subscription ids) are NOT stored in this
field.** Only service-plan GUIDs are recorded as evidence — for example
`3f30311c-6b1e-48a4-ab79-725b469da960` (`M365_COPILOT_BUSINESS_CHAT`) or
`0d0c0d31-fae7-41f2-b909-eaf4d7f26dba` (`Bing_Chat_Enterprise`).
**No PII or UPN values are written to this field.**
Downstream BI queries should filter or account for `Unknown` rows.

### Reconciliation limitation

`fsi_packageid` values (format: `P_...`) are from the Package Management API
id space and are **distinct** from Copilot Studio bot GUIDs. The best-effort
reconciliation join is via `appId` (Package.appId == `fsi_entraappid`) then
`manifestId`. Unmatched package rows receive a `P_...` value as `fsi_agentid`
and **must not** be used in bot-GUID-keyed joins or drift-detection logic.
Reconciliation code guards against cross-id-space false positives; the
`P_...` id space is private to the package layer.

### BI dataset — three governance questions

The combined output of the integrated scanner (`discover_agents.py
--enable-package-api --registry-export ... --resolve-entitlement --output
scan.json`) answers three governance questions directly from `fsi_copilotagent`
and includes two new top-level summary blocks in the JSON output:

- **`registryCorrelation`** — `registryRowCount`, `matched`,
  `unmatchedRegistryRows`, `ambiguousNameSkipped`, `invalidDateWarnings`,
  `status` (`Complete` / `Incomplete` / `Failed`).
- **`entitlementResolution`** — `ownersConsidered`, `paidCount`,
  `chatOnlyCount`, `unknownCount`, `status` (`Complete` / `Incomplete` /
  `Failed`).

The scanner **emits JSON and does not itself write to Dataverse**. Persistence
is handled by the Power Automate flow described in
[flow-configuration.md](flow-configuration.md).

| Question | Columns to query |
|----------|-----------------|
| Who owns agents? | `fsi_ownerupn`, `fsi_ownerid`, `fsi_ownersource`, `fsi_ownermatchconfidence`, `fsi_ownerasofdatetime` |
| Which agents were created in Agent Builder? | `fsi_createdin = "Microsoft 365 Copilot Agent Builder"` |
| Is the owner a paid Copilot user or Copilot Chat only? | `fsi_ownerentitlement`, `fsi_ownerentitlementevidence` |

Filter results by `fsi_ownermatchconfidence` to exclude or flag low-confidence
owner attributions in reports.

## 8-Entity Data Model

The canonical store is eight Dataverse tables (logical names below; all
`OrganizationOwned`). See [dataverse-schema.md](dataverse-schema.md) for the
full column and option-set reference (auto-generated from
`scripts/create_cai_dataverse_schema.py`).

| Logical name | Role |
|--------------|------|
| `fsi_copilotagent` | **Agent master** — one row per discovered agent (the canonical identity). |
| `fsi_caienvironment` | Environment dimension — zone classification, managed-environment state, agent counts. |
| `fsi_caiagentfeature` | **One row per detected feature** (topic, knowledge source, tool/plugin, connector, flow, grounding, AI model, …) resolved from `botcomponent` + the six M:M relationships. |
| `fsi_caiauthshare` | Authentication mode and sharing posture (audience control requires Entra-ID auth + require-sign-in — see prerequisites). |
| `fsi_caibillingentitlement` | Downstream shell — billing/entitlement classification (`createdIn`-keyed, surface-aware spend scope). Populated by a later solution. |
| `fsi_caiusagesignal` | Aggregated usage/invocation signal (counts aggregated at source, not per-event). |
| `fsi_caiworkiqstate` | Downstream shell — Work IQ tier (MCP-in-Copilot-Studio vs Direct Work IQ API) and observed invocation state. Populated by a later solution. |
| `fsi_caicompliancestate` | Per-agent risk level, scan completeness, and violation rollup. |

`fsi_caibillingentitlement` and `fsi_caiworkiqstate` are deliberately scaffolded
as **downstream shells** in this preview: their columns exist so the canonical
model is stable, but the billing-entitlement and Work IQ resolvers are owned by
later solutions in the build graph.

## Scale Engine (target: ~2,000 agents)

The scanner is designed for a tenant with on the order of 2,000 agents across
many environments:

- **Delta change tracking** — environment `bot`/`botcomponent` reads request
  `Prefer: odata.track-changes` and persist the returned `@odata.deltaLink`
  (stored in `fsi_caienvironment.fsi_deltalink`) so subsequent runs pull only
  changes.
- **`$batch`** — Dataverse writes are grouped into OData `$batch` change sets to
  reduce round-trips when upserting agent + feature rows.
- **Throttled parallelism** — environments are scanned with bounded concurrency
  (~10 workers) with **429 backoff** honoring `Retry-After`.
- **Aggregate at source** — usage signals are aggregated into windowed counts
  rather than stored per-event, keeping `fsi_caiusagesignal` bounded.

Idempotency is provided by alternate keys on the canonical tables (see the
schema doc), so re-runs upsert rather than duplicate.

## Scanner Identity (least privilege)

- The scanner authenticates **managed-identity-first**
  (`DefaultAzureCredential` / `ManagedIdentityCredential`); any client secret is
  a dev-only fallback held in Key Vault and accessed via the managed identity.
- Environment **enumeration** requires a Power Platform admin **or** Dynamics 365
  admin role plus ARM access (✅ verified). Per-environment Dataverse **reads**
  require only read access to `bot` / `botcomponent` in each target environment.
- **POLP note (🔎):** granting the scanner System Administrator in every
  environment ("sys-admin-everywhere") is a standing risk. The recommended
  posture is a least-privilege application user with read-only roles scoped to
  the inventory tables; the admin role is required only for the enumeration step.

## ARA Boundary — flagged for ratification

This solution **owns a new canonical entity, `fsi_copilotagent`**, and does
**not** modify `agent-registry-automation`'s legacy `fsi_agentinventory` table
(amendments §2, decision C4 — option (b)). The intended end state is that
`agent-registry-automation` Flow 1 (Daily Discovery) is refactored to **read**
`fsi_copilotagent` after coverage-parity is validated, leaving `fsi_agentinventory`
as a legacy table during migration.

> **This boundary is an assumption pending Jude's ratification.** Adopting
> option (b) avoids a breaking change to a live solution but introduces a
> temporary two-table period until ARA is repointed. The alternative
> (extending `fsi_agentinventory` in place) was not chosen because it would
> couple this foundation to ARA's existing schema and ownership.

## Assumptions and build-time verifications

The README carries the consolidated
[Assumptions and build-time verifications](../README.md#assumptions-and-build-time-verifications)
list. In summary, the items still requiring a live check before this preview is
promoted are: the Layer-1 ARG type live-confirm (🔎), the preview→GA field flips
on the ARG projection (🔎), the `botcomponent` JSON payload schemas (🔎), the
`componenttype` ≥20 metadata refresh (🔎), and the gen-AI/Work IQ configuration
location via live sampling (✅ that the column does not exist; 🔎 where the config
actually lives). Source: `phase1-VERIFICATION-DIGEST.md` §2–§3 and
`phase1-verify-discovery.md` / `phase1-verify-schema.md`.
