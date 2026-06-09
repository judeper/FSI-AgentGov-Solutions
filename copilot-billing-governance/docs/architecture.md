# Architecture

Copilot Billing Governance (CBG) governs **Copilot consumption billing**: it reads
the two billing/credit policy objects, classifies each agent's consumption pathway,
evaluates per-(agent, user) entitlement, and produces a pre-enforcement
**coverage-gap** analysis before any spend control is enforced.

---

## Components

```
                         ┌──────────────────────────────────────────────┐
   Azure Resource Graph  │            Copilot Billing Governance          │
   (PowerPlatformResources)──┐      │                                                │
                              │      │   ┌───────────────┐   ┌───────────────┐        │
   Work IQ usage detection ──┼─────▶│   │  Policy sync  │   │  Group         │        │
   (configuredTier)          │      │   │  (2 objects)  │   │  registry      │        │
                              │      │   │  PAYG + Credit│   │  (3 layers)    │        │
   Microsoft Graph (license) ┘      │   └──────┬────────┘   └──────┬────────┘        │
                                     │          │                   │                 │
                                     │          ▼                   ▼                 │
                                     │   ┌──────────────────────────────────┐        │
                                     │   │   Entitlement engine             │        │
                                     │   │   (switch-on-pathway)            │        │
                                     │   └──────┬───────────────────────────┘        │
                                     │          │ materialize (ttl)                   │
                                     │          ▼                                     │
                                     │   ┌──────────────────────────────────┐        │
                                     │   │ fsi_cbgentitlementmaterialized    │        │
                                     │   │ (per agent × user, cached)        │        │
                                     │   └──────┬───────────────────────────┘        │
                                     │          │ aggregate (per agent)               │
                                     │          ▼                                     │
                                     │   ┌──────────────────────────────────┐        │
                                     │   │ fsi_cbgcoveragegap (monitor-only) │        │
                                     │   └──────────────────────────────────┘        │
                                     └──────────────────────────────────────────────┘
```

### 1. Two policy objects

| Object | Table | Backing | Ceiling | Spend control |
|---|---|---|---|---|
| PAYG billing policy | `fsi_cbgbillingpolicy` | Azure subscription | 50 / tenant | Budget alerts (not a hard-stop) |
| Credit policy | `fsi_cbgcreditpolicy` | Prepaid (no Azure sub) | 10 / tenant | Standalone hard-stop; Chat-only today |

The PAYG policy uses a two-step **add → connect** flow (`fsi_isconnected`). The
credit policy is prepaid with a non-rolling 25,000-credit monthly pack. Surfaces are
tracked via `fsi_spendscope` (Chat is credit-eligible; SharePoint grounding stays
PAYG). See [`entitlement-contract.md`](entitlement-contract.md) §8.

### 2. Three group layers (one admission-gated registry)

A single hardened registry, `fsi_cbgapprovedgrouppolicy`, holds three layers via the
`fsi_grouplayer` discriminator: **maker**, **audience**, and **billing**. The
registry adopts the Agent Sharing Access Restriction Detector (ASARD) admission
gate — a group must be `securityEnabled = true` and **not** `mailEnabled` to be
admitted. This reuses the proven hardened shape rather than cloning the simpler
Unrestricted Agent Sharing Detector (UASD) registry or introducing a careless third
pattern.

### 3. Entitlement engine (switch-on-pathway)

Classifies the agent pathway first (`none` / `mcp-cs` / `mcp-agentbuilder` /
`api-direct` / `metered` / `unmapped`), then applies pathway-specific eligibility,
with an explicit `none → ALLOW` arm, a bounded metered-only `ELSE → block`, a
fail-closed zero-rating arm for `mcp-cs`, and a fail-open-with-anomaly default for
`unmapped`. Decisions are materialized to `fsi_cbgentitlementmaterialized` with a
TTL. Full contract: [`entitlement-contract.md`](entitlement-contract.md).

### 4. Coverage-gap analysis

A **per-agent aggregate** (`fsi_cbgcoveragegap`) produced **monitor-only** first.
One row per agent with eligible/blocked counts, a capped sample of blocked UPNs, the
dominant block reason, and a surface-aware spend scope. Aggregating per agent (not
per agent × user) keeps the output bounded.

### 5. Per-agent caps

`fsi_cbgagentcap` carries a per-agent monthly credit cap and month-to-date
consumption. Because the relevant write APIs (credit-policy CRUD, per-agent caps,
hard-stop) are unproven, enforcement degrades to **detect-and-alert**
(`fsi_cbg_enforcementmode`) where a hard-stop write path is unavailable.

---

## Data flow

1. **Policy sync** (every 15 minutes): read PAYG + credit policy state into
   `fsi_cbgbillingpolicy` / `fsi_cbgcreditpolicy`; snapshot tenant policy counts for
   the 50 / 10 ceilings.
2. **Classify + evaluate**: for each agent, classify the pathway from ARG
   `createdIn` + Work IQ `configuredTier`, evaluate entitlement, materialize the
   decision with a TTL.
3. **Coverage-gap** (nightly): aggregate per agent into `fsi_cbgcoveragegap`,
   monitor-only.

See [`flow-configuration.md`](flow-configuration.md) for the manual build of the two
flows (no exported flow JSON is shipped).

---

## Build dependency graph

CBG is **not** built as a single linear unit; it splits along the inventory /
Work IQ dependency boundary:

| Sub-deliverable | Depends on | Can start |
|---|---|---|
| Policy read (2 objects) | — | Immediately (parallel with `copilot-agent-inventory`) |
| Admission-gated group registry | ASARD pattern (in-repo) | Immediately |
| Coverage-gap **shell** (monitor-only) | — | Immediately |
| Schema + cost tags | — | Immediately |
| Pathway classifier | `copilot-agent-inventory` (`createdIn`) | After inventory store |
| Entitlement engine | `work-iq-usage-detection` (`configuredTier`) | After Work IQ detection |
| Work IQ gap-math | `work-iq-usage-detection` | After Work IQ detection |
| Per-agent caps | Policy read | After policy read |

> **Assumption:** the Pillar-2-dependent sub-deliverables consume `configuredTier`
> from `work-iq-usage-detection`, whose GA / consumption-billing switch is **June 16
> 2026**. Until the sibling solutions land, the classifier and engine run on
> sample/fixture inputs.

---

## Authentication

All automation follows the repository's **managed-identity-first** standard. The
shared `DataverseClient` accepts a token from any source, so the scheduled host
should use a system-assigned (or user-assigned) managed identity. Client secrets are
a legacy development-only fallback. See [`prerequisites.md`](prerequisites.md).
