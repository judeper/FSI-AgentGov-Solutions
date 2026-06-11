---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: optimize
---
# Copilot Billing Governance

> **Version:** v0.1.0-preview
> **Status:** Preview
> **Validated against framework version:** v1.6.0
> **Upstream Microsoft dependency:** Mixed — Copilot Credits consumption billing from June 16 2026; credit policies Chat-only today
> **Last Verified:** 2026-06-09

Governance for **Copilot consumption billing** — the two policy objects
(pay-as-you-go and prepaid credits), a switch-on-pathway entitlement engine,
per-agent caps, and a pre-enforcement **coverage-gap** analysis. This solution
targets the **US commercial Microsoft 365 / Power Platform cloud**.

## Overview

When agents begin consuming metered Copilot capabilities, two questions need a
governed answer: *which billing or credit policy backs this agent's spend*, and
*which users are entitled to incur that spend*. Copilot Billing Governance (CBG)
reads the two policy objects, classifies each agent's consumption pathway,
evaluates per-(agent, user) entitlement, and produces a per-agent coverage-gap
report **before** any spend control is turned on.

CBG supports compliance with **Control 3.5 (Cost Allocation and Budget Tracking)**
and contributes to **1.18 (Application-Level Authorization and RBAC)** and
**1.14 (Data Minimization and Agent Scope Control)**. It does not, on its own,
satisfy any regulation; organizations should verify their configuration meets their
specific obligations.

CBG reads — rather than re-discovers — the agent dimension from
`copilot-agent-inventory` and the usage tier from `work-iq-usage-detection`.

## Related Controls

| Control | Title | How this solution contributes |
|---|---|---|
| [3.5](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.5-cost-allocation-and-budget-tracking/) | Cost Allocation and Budget Tracking | Reads PAYG and credit policy state, estimates per-feature credit spend, and reports per-agent coverage gaps |
| [1.18](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.18-application-level-authorization-and-role-based-access-control-rbac/) | Application-Level Authorization and RBAC | Entitlement decisions gate which cohorts may invoke a metered agent |
| [1.14](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.14-data-minimization-and-agent-scope-control/) | Data Minimization and Agent Scope Control | Surface-aware spend scope (Chat vs SharePoint) keeps entitlement within declared scope |

### Proposed framework control 2.27 (cross-repo follow-up)

The entitlement archetype CBG implements — *who is entitled to consume metered
agent capabilities under which billing or credit policy* — is not cleanly expressed
by any existing framework control. This is recorded as a **proposal for the
companion framework repo `judeper/FSI-AgentGov`**, not a control implemented by this
manifest (which lists only the existing IDs `3.5`, `1.18`, `1.14`).

**Proposed Control 2.27 — Consumption-Entitlement Governance** (Pillar 2,
Management). Rule-out of extending an existing control first, per review:

- **Not 2.26 (Entra Agent ID — Identity Governance for Agents).** 2.26 governs the
  agent's *identity lifecycle*; consumption entitlement governs *a user's permission
  to spend*. Folding it into 2.26 would conflate identity provisioning with billing
  authorization.
- **Not 1.18 (Application-Level Authorization and RBAC).** 1.18 governs *functional*
  authorization; consumption entitlement adds a *cost/billing* dimension (entitlement
  to incur metered spend, under which policy, on which surface) that 1.18 does not
  express. 1.18 is a necessary input, not a substitute.

2.27 would pair with 3.5: 3.5 is the Reporting-pillar view, 2.27 the
Management-pillar control governing the entitlement decisions 3.5 reports on.
Placement and ratification are open with the framework owner. Full wording in
[`docs/entitlement-contract.md`](docs/entitlement-contract.md) §9.

## Architecture

Full detail in [`docs/architecture.md`](docs/architecture.md). In summary, four
parts:

1. **Two policy objects.** PAYG billing policy (`fsi_cbgbillingpolicy`,
   Azure-subscription-backed, tenant ceiling 50, two-step add → connect, budget
   alerts only — not a hard-stop) and Copilot credit policy
   (`fsi_cbgcreditpolicy`, prepaid, tenant ceiling 10, standalone hard-stop,
   Chat-only today — SharePoint grounding stays PAYG). Three configurations:
   credit-only, credit + PAYG, PAYG-only.
2. **Three group layers, one admission-gated registry.**
   `fsi_cbgapprovedgrouppolicy` holds maker, audience, and billing groups, gated on
   `securityEnabled = true` and not `mailEnabled` — reusing the hardened ASARD
   registry shape rather than cloning the simpler UASD registry.
3. **Switch-on-pathway entitlement engine.** Classifies the agent pathway first
   (`none` / `mcp-cs` / `mcp-agentbuilder` / `api-direct` / `metered` / `unmapped`),
   then applies pathway-specific eligibility, materializing each decision to
   `fsi_cbgentitlementmaterialized` with a TTL.
4. **Coverage-gap analysis.** A per-agent aggregate (`fsi_cbgcoveragegap`),
   monitor-only first, with a capped sample of blocked UPNs and a surface-aware
   spend scope.

### The entitlement contract (the keystone)

The engine **switches on the consumption pathway** rather than denying by default.
There is an explicit `none → ALLOW (eligibility N/A)` arm for the agent majority, a
bounded `ELSE → block` **only inside the metered pathway**, a **zero-rating-resolved**
`mcp-cs` arm (license sufficient on a zero-rated M365 surface, per the June 2026
Licensing Guide footnotes 6 & 7; reverts to fail-closed when set false), and a
`unmapped → fail-open-with-anomaly` default so a classifier defect does not deny users.
Full decision tree, pseudocode, and the zero-rating analysis are in
[`docs/entitlement-contract.md`](docs/entitlement-contract.md).

## Components

```
copilot-billing-governance/
├── README.md
├── CHANGELOG.md
├── manifest.yaml
├── docs/
│   ├── architecture.md            # 2 objects + 3 groups + engine + coverage-gap
│   ├── entitlement-contract.md    # switch-on-pathway decision tree + pseudocode
│   ├── prerequisites.md           # licensing, permissions, managed-identity model
│   ├── dataverse-schema.md        # auto-generated; do not hand-edit
│   └── flow-configuration.md      # 15-min policy sync + nightly coverage-gap
├── scripts/
│   ├── create_cbg_dataverse_schema.py     # schema + --output-docs
│   ├── Get-BillingPolicyInventory.ps1     # PAYG + credit policy read (scope + connected surfaces)
│   ├── Get-CopilotEntitlement.ps1         # per-user entitlement resolver (real Graph + PAYG inputs → engine)
│   └── Invoke-EntitlementEvaluation.ps1   # switch-on-pathway engine + coverage-gap
└── templates/
    ├── coverage-gap.sample.json
    └── entitlement-decision.sample.json
```

## Prerequisites

See [`docs/prerequisites.md`](docs/prerequisites.md). In brief: Microsoft 365 Copilot
licensing; PAYG and/or prepaid credit policy; an Azure subscription for PAYG; Power
Platform Premium and Dataverse capacity; and Graph `User.Read.All` / `Group.Read.All`
granted to a managed identity. Roles: Microsoft 365 Admin (billing/credit policy),
Azure subscription Owner/Contributor (PAYG), Entra security-group admin (group
registry), Power Platform Admin (Dataverse and flows).

## Deployment

1. **Deploy the schema.** `python scripts/create_cbg_dataverse_schema.py`
   (add `--output-docs` to regenerate `docs/dataverse-schema.md`).
2. **Register groups.** Add maker, audience, and billing security groups to
   `fsi_cbgapprovedgrouppolicy` (security-enabled, not mail-enabled).
3. **Read policy state.** Run
   [`scripts/Get-BillingPolicyInventory.ps1`](scripts/Get-BillingPolicyInventory.ps1)
   to inventory PAYG and credit policies against the 50 / 10 ceilings.
4. **Build the flows.** Follow
   [`docs/flow-configuration.md`](docs/flow-configuration.md) to build the 15-minute
   policy-sync flow and the nightly coverage-gap flow (no exported flow JSON is
   shipped).
5. **Resolve per-user entitlement inputs (real tenant data).**
   [`scripts/Get-CopilotEntitlement.ps1`](scripts/Get-CopilotEntitlement.ps1) reads each
   user's Copilot license (by the paid service-plan allowlist, including transitive group
   assignments) and PAYG / credit coverage, and emits the engine-ready per-user booleans
   plus a Find-No-Filter "blocked" lens. Supply the audience UPNs (from
   `copilot-agent-inventory`); for the policy dimension, prefer `-BillingPolicyInputPath`
   (the normalized `Get-BillingPolicyInventory.ps1` output) while the billing-policy REST
   schema remains unproven.
6. **Run coverage-gap analysis monitor-only.**
   [`scripts/Invoke-EntitlementEvaluation.ps1`](scripts/Invoke-EntitlementEvaluation.ps1)
   evaluates the resolved entitlement inputs and writes per-agent gaps; confirm rows in
   `fsi_cbgcoveragegap` before enabling any enforcement.

Authentication is **managed-identity-first**; client secrets are a legacy
development-only fallback. See [`docs/prerequisites.md`](docs/prerequisites.md).

## Assumptions and build-time verifications

These are flagged for ratification with Jude and re-verification against Microsoft
sources.

- **Switch-on-pathway replaces deny-by-default.** The corrected contract uses an
  explicit `none → ALLOW` arm and a bounded metered-only `ELSE → block`. Assumption:
  the agent majority is `none`-pathway (consumes no metered features).
- **Zero-rating is RESOLVED per the June 2026 Licensing Guide (footnotes 6 & 7).** A
  Microsoft 365 Copilot–licensed user on a Microsoft 365 surface under their own
  identity is included in the Microsoft 365 Copilot User SL at no additional charge, so
  `fsi_zeroratingresolved` now defaults `true` and a Copilot-licensed `mcp-cs` user on a
  zero-rated surface resolves to **Allow** — the license is sufficient, no credit scope
  required. Non-Microsoft-365 surfaces, unlicensed users, and the
  generative-answer-with-tenant-grounding / beyond-fair-use refinements remain
  credit-metered — confirm per tenant. Set `-ZeroRatingResolved:$false` to revert to the
  conservative fail-closed posture.
- **Write APIs are unproven.** Credit-policy CRUD, per-agent caps, and hard-stop may
  have no public write API. Where absent, enforcement degrades to **detect-and-alert**
  (`fsi_cbg_enforcementmode`); CBG ships read/analysis-first.
- **Policy ceilings.** PAYG **50** and credit **10** per tenant are encoded as the
  `MaxValue` on the `fsi_policycountsnapshot` columns and surfaced in the schema docs.
- **Upstream dependencies.** `createdIn` comes from `copilot-agent-inventory` (Azure
  Resource Graph `PowerPlatformResources`); `configuredTier` from
  `work-iq-usage-detection`. Both siblings are built in the same
  `feat/copilot-agent-governance` wave; until they are catalog-registered, the engine
  runs on fixture inputs via `-InputPath`. Work IQ GA / consumption-billing switch is
  **June 16 2026**.
- **Per-user inputs from real tenant data.** `Get-CopilotEntitlement.ps1` produces the
  engine's per-user booleans from Microsoft Graph (license by the paid service-plan
  allowlist — including transitive group assignments — with `Bing_Chat_Enterprise` and
  other confusable plans explicitly denied) and PAYG / credit coverage (mapped to
  `inCreditScopeGroup`, with an "All Users" policy collapsing the blocked set to zero per
  capability). PAYG coverage is granted only from a policy the resolver can fully parse:
  a policy whose connection state, capability surface, or scope cannot be determined is
  treated as **not covering** (fail-closed) and routed to a `needsManualReview` list with
  a `coverageUncertain` flag, so unlicensed in-scope users are not silently under-reported
  as entitled. A user whose Graph read fails is recorded **unresolved** and excluded —
  never reported as "blocked" — because misclassifying a licensed user is a serious,
  customer-facing error; fail-open is reserved for that transient per-user read case. The
  billing-policy REST schema is **unproven**; prefer `-BillingPolicyInputPath` (the
  `Get-BillingPolicyInventory.ps1` output) over the best-effort live read.
- **2.27 is a proposal**, not an implemented control in this manifest.

## Changelog

See [`CHANGELOG.md`](CHANGELOG.md).
