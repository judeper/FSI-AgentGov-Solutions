# Architecture - Copilot Agent Inventory

> **Status:** `0.2.0-preview`. This document describes the intended architecture
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

## Three-Layer Discovery

No single API returns a complete, tenant-wide agent inventory, so discovery
composes three layers and reconciles them.

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

## Scan Completeness

Lite / Agent Builder agents are recorded with
`fsi_caicompliancestate.fsi_scancompleteness = "Incomplete Scan"` (✅ verified):
no public API returns their full definition (instructions + knowledge +
capabilities). The Graph Package Management API is beta, is delegated-only
(which blocks unattended service-principal automation), and returns a minimal
definition; the full manifest is available only via a manual export. Recording
these as `incomplete-scan` keeps the coverage limitation explicit in the
record-keeping trail rather than implying a completeness the platform does not
support.

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
