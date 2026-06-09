# Entitlement Contract — Switch-on-Pathway

> **Status:** Preview (v0.1.0-preview). This is the corrected entitlement contract
> for Copilot Billing Governance. It replaces an earlier deny-by-default design
> (`ELSE → block`) that would have blocked the agent majority. See
> [Assumptions](#assumptions-and-build-time-verifications).

This document is the single source of truth for **how the entitlement engine
decides whether a given user may invoke a given agent** under Copilot consumption
billing. It is implemented as a decision tree plus pseudocode; the runnable
skeleton lives in [`scripts/Invoke-EntitlementEvaluation.ps1`](../scripts/Invoke-EntitlementEvaluation.ps1).

---

## 1. Design principle: switch on pathway, not deny-by-default

The load-bearing correction is that the engine **classifies the agent's
consumption pathway first**, then applies pathway-specific eligibility. A single
global `ELSE → block` would deny the large population of agents that consume no
metered Copilot features. Instead:

- There is an explicit **`none → ALLOW (eligibility N/A)`** arm that unblocks the
  agent majority.
- A bounded `ELSE → block` exists **only inside a metered pathway**, where a user
  who is in no eligible cohort is correctly blocked.
- An **unmapped pathway fails open with an anomaly** — a detection defect must not
  deny a user. The anomaly is recorded for follow-up rather than silently allowed.

This contract supports compliance with **Control 3.5 (Cost Allocation and Budget
Tracking)**, **Control 1.18 (Application-Level Authorization and RBAC)**, and
**Control 1.14 (Data Minimization and Agent Scope Control)**. It does not, on its
own, satisfy any regulation; organizations should verify their configuration meets
their specific obligations.

---

## 2. Inputs

| Input | Source | Used for |
|---|---|---|
| `createdIn` | Azure Resource Graph (`PowerPlatformResources` table) | Pathway classification (which environment/tooling built the agent) |
| `configuredTier` | Work IQ usage detection (`work-iq-usage-detection` solution) | Pathway classification + whether the agent uses metered features |
| Tenant-grounding signal | Agent configuration (botcomponent) | Zero-rating modifier (grounded answers bill even for licensed users) |
| User Copilot license | Microsoft Graph license read | Per-pathway eligibility |
| Group membership | Entra security groups in the admission-gated registry (`fsi_cbgapprovedgrouppolicy`) | Eligible-cohort / credit-scope checks |
| Credit / PAYG policy state | `fsi_cbgcreditpolicy`, `fsi_cbgbillingpolicy` | Surface (Chat vs SharePoint) and policy availability |

> **Assumption (dependency):** `createdIn` and `configuredTier` are produced by the
> sibling solutions `copilot-agent-inventory` and `work-iq-usage-detection`. Until
> those land, the engine operates on sample/fixture inputs (see the script's
> `-InputPath` parameter).

---

## 3. Pathway classification

`ClassifyPathway(agent)` maps an agent to one option of the `fsi_cbg_pathway` global
option set. **`configuredTier` is the authoritative signal and is evaluated first**;
`createdIn` is consulted **only as a last-resort fallback** when `configuredTier` is
empty or unrecognized. This ordering is load-bearing: it keeps a Copilot-Studio
`createdIn` from overriding an authoritative non-metered tier and forcing the agent
majority into the fail-closed `mcp-cs` arm.

The sibling `work-iq-usage-detection` classifier emits one of the following
`configuredTier` values (compared lowercased): `NotConfigured`,
`NativeMcpCopilotStudio`, `NativeApiDirect`, `Adjacent`.

### 3a. Authoritative `configuredTier` mapping (evaluated first)

| `configuredTier` (Work IQ) | Pathway (`fsi_cbg_pathway`) |
|---|---|
| `NativeMcpCopilotStudio` | `mcp-cs` |
| `NativeApiDirect` | `api-direct` |
| `NotConfigured`, `Adjacent` (and `none` / `classic` / `non-metered` synonyms) | `none` |
| `metered` / `generative` / `grounded` / `agent-action` / `premium` | `metered` |

`NotConfigured` and `Adjacent` are **non-metered → `none` → ALLOW (eligibility N/A)**,
which unblocks the agent majority.

### 3b. `createdIn` fallback (only when `configuredTier` is empty / unrecognized)

| `createdIn` signal | Pathway (`fsi_cbg_pathway`) |
|---|---|
| Copilot Studio environment | `mcp-cs` |
| Agent Builder | `mcp-agentbuilder` |
| API / declarative / direct-line / custom | `api-direct` |
| Missing or contradictory signals | `unmapped` (fail-open with anomaly) |

The resulting pathway carries the meaning below regardless of which signal produced it:

| Pathway (`fsi_cbg_pathway`) | Meaning |
|---|---|
| `none` | Consumes no metered Copilot features (classic / no generative, no grounding) |
| `mcp-cs` | Copilot Studio–built MCP agent |
| `mcp-agentbuilder` | Microsoft 365 Copilot Agent Builder MCP agent |
| `api-direct` | Direct API / declarative agent on an owned channel |
| `metered` | Agent on a metered consumption path not covered above |
| `unmapped` | Classification could not be resolved (missing or contradictory signals) |

---

## 4. Decision tree

```
EvaluateEntitlement(agent, user):
  pathway ← ClassifyPathway(agent)        # Work IQ configuredTier first; createdIn fallback

  switch pathway:

    case none:                            # ── the agent majority ──
        return ALLOW            reason = "eligibility N/A"

    case mcp-agentbuilder:
        if user.hasCopilotLicense: return ALLOW
        else:                      return BLOCK   reason = "Missing license"

    case api-direct:
        if user ∈ apiAudienceGroup: return ALLOW
        else:                       return BLOCK  reason = "No eligible cohort"

    case mcp-cs:                          # ── zero-rating CONFLICT: fail-closed ──
        if not user.hasCopilotLicense:    return BLOCK   reason = "Missing license"
        if ZeroRatingResolved AND zeroRated(agent.surface):
                                          return ALLOW
        if user ∈ creditScopeGroup:       return ALLOW
        return FAIL_CLOSED                reason = "Zero-rating unresolved"

    case metered:
        if user ∈ eligibleCohort(agent):  return ALLOW
        else:                             return BLOCK   reason = "No eligible cohort"
                                          # ← the ONLY unbounded-population ELSE,
                                          #   and it is bounded to a metered pathway

    default:                              # unmapped
        return FAIL_OPEN_ANOMALY          reason = "Unmapped pathway"
        # a detection defect must not deny a user; the anomaly is recorded
```

Decisions map to the `fsi_cbg_decision` option set: `Allow`, `Block`,
`Allow - Eligibility N/A`, `Fail-open - Anomaly`, `Fail-closed - Zero-rating Unresolved`.
Block reasons map to `fsi_cbg_blockreason`.

---

## 5. Zero-rating modifier — CONFLICTED, fail-closed interim

> **⚠️ Unresolved-pending-PDF.** Whether Copilot-Studio–built generative and
> tenant-grounded responses are **zero-rated** for Microsoft 365 Copilot–licensed
> users is **in conflict** across current sources. The interim encoding is
> **fail-closed**: it is not treated as settled.

Build-time finding: **CS-built generative / grounded responses bill even for
M365-licensed users.** Therefore the `mcp-cs` arm requires a license **AND**
(the surface is confirmed zero-rated **OR** the user is in credit scope):

```
mcp-cs eligible  ⇔  hasCopilotLicense AND ( (ZeroRatingResolved AND zeroRated(surface))
                                            OR user ∈ creditScopeGroup )
```

- `ZeroRatingResolved` is carried on each `fsi_cbgentitlement` row and **defaults to
  `false`**, which keeps the rule fail-closed.
- The conflict is to be resolved against the **June 2026 Microsoft Copilot Licensing
  Guide PDF** (highest-priority re-pull). When that source confirms zero-rating, set
  `ZeroRatingResolved = true` for the affected surfaces and re-run materialization.
- Until then, `mcp-cs` users who are licensed but not in credit scope resolve to
  **`Fail-closed - Zero-rating Unresolved`**, not a silent allow.

This is a deliberately conservative interim posture to avoid under-counting spend;
it is expected to relax once the licensing source is confirmed.

---

## 6. Materialized decision cache (`fsi_cbgentitlementmaterialized`)

Recomputing the full decision tree per read does not scale to large
(agent × user) populations. Each decision is materialized to
`fsi_cbgentitlementmaterialized` with a **time-to-live** (`fsi_ttlexpiresat`).
Reads consult the cache; expired or missing entries are recomputed. The cache
stores the pathway, decision, block reason, spend scope, and source policy so a
decision is auditable without replaying inputs.

> **Assumption:** TTL duration is intentionally left as a deployment parameter
> (`-CacheTtlMinutes`, default documented in the script). "Decide late": tune it
> from observed input-change cadence rather than pre-committing a value here.

---

## 7. Coverage-gap analysis (the load-bearing pre-enforcement deliverable)

Before any enforcement, the solution runs a **per-agent coverage-gap aggregate**
in **monitor-only** mode. For each agent it records one `fsi_cbgcoveragegap` row:

| Field (logical name) | Meaning |
|---|---|
| `fsi_agentid` | Analyzed agent |
| `fsi_pathway` | Classified pathway |
| `fsi_eligibleusers` | Count of users eligible under current policies |
| `fsi_blockeduserscount` | Count of intended users who would be blocked |
| `fsi_blockedsampleupns` | **Capped** JSON sample of blocked UPNs (bounded to avoid row blow-up) |
| `fsi_blockreasonsummary` | Dominant block reason across the cohort |
| `fsi_spendscope` | Surface-aware scope (Chat vs SharePoint) |
| `fsi_groupsizepartition` | Total intended-audience size (partitions large groups above threshold **T**) |
| `fsi_monitoronly` | `true` first — gap rows take no enforcement action |
| `fsi_retainuntil` | Retention horizon for the aggregate |

Aggregating **per agent** (not per agent × user) keeps the output bounded; a naive
per-pair materialization of every blocked user would produce a 10⁶–10⁷-row blow-up.
The capped UPN sample preserves investigability without the row explosion.

### 7.1 Per-feature credit rates (coverage-gap cost estimate)

Coverage-gap spend is estimated from Microsoft-published per-feature **Copilot
credit** rates. These are reference constants (not a Dataverse table); verify
current values against Microsoft licensing documentation before relying on them.

| Feature | Credits |
|---|---|
| Classic answer | 1 |
| Generative answer | 2 |
| Agent action | 5 |
| Tenant-graph grounding | 10 |
| Agent flow | 13 per 100 flow actions |
| AI tools | 1 / 15 / 100 (tiered) |
| Content understanding | 8 per page |
| Voice | 10 / 35 / 75 per minute (tiered) |

Pricing context: **$0.01 per credit**; the prepaid pack is **25,000 credits per
month, non-rolling** (unused credits do not carry over). PAYG consumption is metered
against an Azure subscription with **budget alerts only — not a hard-stop**.

> **Language caveat:** these figures support cost *estimation*; they do not produce
> a billing-accurate invoice. Organizations should reconcile against the Microsoft
> 365 admin center and Azure cost reporting.

---

## 8. Two policy objects and three configurations

| | PAYG billing policy (`fsi_cbgbillingpolicy`) | Credit policy (`fsi_cbgcreditpolicy`) |
|---|---|---|
| Backing | Azure subscription | Prepaid (no Azure subscription) |
| Tenant ceiling | **50** | **10** |
| Setup | Two-step **add → connect** | Standalone |
| Spend control | Budget **alerts** (not a hard-stop) | Standalone **hard-stop** |
| Surfaces | All metered surfaces incl. SharePoint grounding | **Chat-only today**; SharePoint stays PAYG |

Three supported configurations: **credit-only**, **credit + PAYG**, and **PAYG-only**.
The `fsi_spendscope` field carries the surface (Chat vs SharePoint) so the engine and
coverage-gap remain surface-aware.

---

## 9. Proposed framework control 2.27 (cross-repo follow-up)

> **This is a proposal for the companion framework repo `judeper/FSI-AgentGov`, not
> a control implemented by this manifest.** `manifest.yaml` intentionally lists only
> existing framework controls (`3.5`, `1.18`, `1.14`).

**Proposed Control 2.27 — Consumption-Entitlement Governance (Pillar 2,
Management).** Governs *who is entitled to consume metered agent capabilities under
which billing or credit policy*, distinct from identity governance and
authorization.

**Why a new control rather than extending an existing one (rule-out, per the owl
review):**

- **Not 2.26 (Entra Agent ID — Identity Governance for Agents).** 2.26 governs the
  *agent's identity lifecycle*. Consumption entitlement governs *a user's
  permission to spend* on an agent's metered features — a billing/authorization
  archetype, not an identity-provisioning archetype. Folding it into 2.26 would
  conflate two different control objectives.
- **Not 1.18 (Application-Level Authorization and RBAC).** 1.18 governs *functional*
  authorization (can this principal call this capability). Consumption entitlement
  adds a *cost/billing* dimension (is this principal entitled to incur metered
  spend, under which policy, on which surface). 1.18 is a necessary input but does
  not express the billing-scope or zero-rating semantics.

2.27 would pair with **3.5 (Cost Allocation and Budget Tracking)** — 3.5 is the
Reporting-pillar view; 2.27 is the Management-pillar control that governs the
entitlement decisions 3.5 reports on. Placement (Management vs Reporting) is open
for ratification with the framework owner.

---

## Assumptions and build-time verifications

- **Deny-by-default replaced.** The brief's global `ELSE → block` is replaced by
  switch-on-pathway with an explicit `none → ALLOW` arm and a bounded metered-only
  `ELSE`. Assumption: the agent majority is `none`-pathway.
- **Zero-rating CONFLICT → fail-closed interim.** Carried as unresolved pending the
  June 2026 Licensing Guide PDF. Not settled.
- **`createdIn` / `configuredTier` are upstream.** Sourced from
  `copilot-agent-inventory` (ARG `PowerPlatformResources`) and
  `work-iq-usage-detection`. Work IQ GA / consumption-billing switch is **June 16
  2026**.
- **Write-API unproven.** Credit-policy CRUD, per-agent caps, and hard-stop may have
  no public write API; enforcement degrades to **detect-and-alert** (see
  `fsi_cbg_enforcementmode`).
- **Ceilings.** PAYG **50** / credit **10** per tenant are encoded as `MaxValue` on
  the `*_policycountsnapshot` columns and surfaced in docs.
- **2.27 is a proposal.** Not an implemented control in this manifest.
