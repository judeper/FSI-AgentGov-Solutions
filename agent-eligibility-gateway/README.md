# Agent Eligibility Gateway

> **Status:** Preview (v0.1.0-preview) — optional runtime allow/deny gateway for **owned** custom-web / Direct Line agent channels only. Suitable for reference-gateway validation in a non-production environment; customer-facing deployment is optional and conditional (see [Deployment](#deployment)).
> **Upstream Microsoft dependency:** GA — Azure API Management is generally available; this gateway applies only to owned custom-web/Direct Line channels — first-party Teams/M365/SharePoint surfaces cannot host middleware and rely on native controls plus telemetry drift.

An optional Azure API Management (APIM) gateway that performs a runtime allow/deny decision in front of an agent endpoint. It validates the caller's Microsoft Entra ID token, checks audience / Viewers membership, reads the agent's compliance posture and billing pathway from the governance store, applies the corrected billing entitlement contract, and emits a per-decision audit record. It supports compliance with the authorization and reporting controls listed in [Related Controls](#related-controls); it does not replace the native Power Platform and Managed Environment controls that govern first-party surfaces.

## Owned channels vs. first-party surfaces (read this first)

This gateway is a piece of middleware. **First-party agent surfaces — Microsoft Teams, Microsoft 365 Copilot, and SharePoint — cannot host custom middleware**, so a request to an agent on those surfaces never traverses this gateway. The gateway is therefore scoped to **owned channels that the organization fronts itself**: custom web chat (Direct Line / Web Chat embedded in an owned site or app) and Direct Line API integrations.

| Channel | Can this gateway sit in front of it? | How it is governed |
|---|---|---|
| Owned custom web chat (Direct Line / Web Chat) | **Yes** | Runtime allow/deny at the APIM gateway (this solution) |
| Direct Line API (owned client/app) | **Yes** | Runtime allow/deny at the APIM gateway (this solution) |
| Microsoft Teams | No | Native Managed Environment sharing (`bot-*` extended settings) + telemetry-drift detection |
| Microsoft 365 Copilot | No | Native controls + telemetry-drift detection |
| SharePoint | No | Native controls + telemetry-drift detection |

The boundary is deliberate: the gateway provides a **hard allow/deny at request time on owned channels**, while first-party surfaces rely on native sharing/audience controls (which apply with roughly an hour of enforcement latency) plus the detective telemetry-drift solutions in this repository. The two layers are complementary, not interchangeable. See [docs/architecture.md](docs/architecture.md) for the control-layer summary.

## Architecture

```text
Client app  (owned custom-web / Direct Line channel)
   |
   v
Microsoft Entra ID sign-in   (precondition: Entra ID auth + require-users-to-sign-in = ON)
   |  bearer token
   v
Agent Eligibility Gateway  (Azure API Management)
   |  - validate-jwt            tenant OpenID config, audience, issuer, tid claim   -> 401 on failure
   |  - audience / Viewers gate group membership                 (controls 1.1, 1.18) -> 403 on failure
   |  - governance-store lookup managed identity reads fsi_copilotagent
   |  - entitlement contract    switch-on-pathway (corrected)                          -> 403 on deny
   |  - decision telemetry      one structured record per request
   |
   +--> allow --> Agent endpoint  (Copilot Studio / custom agent backend)
   |
   +--> telemetry sink --> fsi_aegdecisionlog  (per-decision audit, control 3.8)
```

The runtime path is `Client -> Entra sign-in -> Eligibility Gateway (APIM) -> agent endpoint -> telemetry sink`. APIM responsibilities, in order:

1. **`validate-jwt`** against the tenant OpenID configuration (audience, issuer, and `tid` required-claim). Token failures return **401**.
2. **Audience / Viewers gate** — the caller must be a member of the agent's audience (Viewers) security group, supporting controls 1.1 and 1.18. Out-of-policy callers receive **403**.
3. **Governance-store lookup** — the gateway **managed identity** reads the agent's compliance posture and billing pathway from `fsi_copilotagent` in the governance store.
4. **Entitlement contract (switch-on-pathway)** — applies the corrected billing eligibility logic (see [Entitlement contract](#entitlement-contract-switch-on-pathway)). Denies inside a metered pathway return **403** with a governed message.
5. **Decision telemetry** — one structured record per request is emitted to the configured sink, which lands it in `fsi_aegdecisionlog` (control 3.8).

### Entitlement contract (switch-on-pathway)

The gateway applies the corrected entitlement contract. Eligibility is evaluated **only inside a metered pathway**; a non-metered request is not denied for billing reasons.

| Condition | Decision |
|---|---|
| Pathway `none` | **Allow** — billing eligibility is not applicable |
| Agent is non-compliant in the governance store | **Deny (403)** |
| Pathway `metered` **and** caller is in no eligible cohort | **Deny (403)** |
| Pathway unmapped / unknown | **Allow**, stamped as an anomaly — a detection defect must not deny a user |
| Any other classified pathway (`mcp-cs`, `mcp-agentbuilder`, `api-direct`) | **Allow** |

A `none` pathway always resolves to allow; a deny is raised only inside a metered pathway when the caller belongs to no eligible cohort. The fail-open behaviour on an unmapped pathway is intentional: a classification gap is treated as an anomaly to investigate, not as grounds to block a signed-in, audience-authorized user.

## Prerequisites

A condensed list — see [docs/prerequisites.md](docs/prerequisites.md) for the full version with role and configuration detail.

- An **Azure API Management** instance and Azure contributor rights on its resource group.
- A **gateway Entra ID app registration** and the **audience / Viewers security group(s)** that define each agent's audience.
- A **managed identity** for the gateway with read access to the governance store (`fsi_copilotagent`, `fsi_cbgentitlementmaterialized`).
- The **governance store** populated by the `copilot-agent-inventory` and `copilot-billing-governance` sibling solutions (the gateway reads, it does not populate, those tables).
- Each target agent must satisfy the [Entra-ID-auth precondition](#assumptions-and-build-time-verifications); validate it with [`scripts/Test-AgentEligibilityPrecondition.ps1`](scripts/Test-AgentEligibilityPrecondition.ps1).

## Deployment

> Reference gateway first; customer deployment is optional and conditional.

This solution follows a **design-validation-before-deployment** split:

1. **Reference gateway (recommended first step).** Stand up the gateway in a **non-production environment** and exercise the entitlement contract end-to-end against representative agents and cohorts. This validates the corrected contract (allow/deny outcomes, anomaly fail-open, decision logging) without affecting production traffic. The reference build is the primary deliverable of this preview.
2. **Customer deployment (optional / conditional).** Promoting the gateway in front of a production owned channel is **optional** and depends on whether the customer operates owned custom-web / Direct Line channels at all. Customers whose agents run only on first-party surfaces do not deploy this gateway; they rely on native controls plus telemetry-drift detection.

Step-by-step build instructions live in [docs/apim-gateway-setup.md](docs/apim-gateway-setup.md). The optional decision-log table is created with [`scripts/create_aeg_dataverse_schema.py`](scripts/create_aeg_dataverse_schema.py) (`--output-docs` regenerates [docs/dataverse-schema.md](docs/dataverse-schema.md)).

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.1 - Restrict Agent Publishing by Authorization](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.1-restrict-agent-publishing-by-authorization.md) | Adds a runtime allow/deny check on owned channels so only members of the agent's audience / Viewers group reach the endpoint; complements publishing-time authorization (this gateway does not replace native publishing controls) |
| [1.18 - Application-Level Authorization and Role-Based Access Control (RBAC)](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.18-application-level-authorization-and-role-based-access-control-rbac.md) | Performs application-level authorization at the API Management tier — token validation, group-based audience gating, and the billing entitlement contract — before a request reaches the agent |
| [3.8 - Copilot Hub and Governance Dashboard](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard.md) | Emits per-decision audit rows to `fsi_aegdecisionlog` for surfacing on the Copilot Hub / governance dashboard |

## Assumptions and build-time verifications

The decisions below were made while scaffolding this preview and are flagged as assumptions to confirm during ratification.

- **Entra-ID-auth precondition (build-time verified).** The gateway depends on a signed-in Microsoft Entra ID user context. A target agent must use Microsoft Entra ID authentication (`bot.authenticationmode` = Integrated or Custom Azure Active Directory) **with** require-users-to-sign-in ON (`bot.authenticationtrigger` = Always). **No-authentication and Generic OAuth2 agents do not qualify** — being "authenticated" by a non-Microsoft provider is not sufficient, because sharing-based audience control is unavailable. Security groups act as **Viewers (chat)** only. Assert this per agent with `Test-AgentEligibilityPrecondition.ps1` before onboarding.
- **Owned channels only.** First-party Teams / Microsoft 365 Copilot / SharePoint surfaces cannot host this middleware; the gateway applies solely to owned custom-web / Direct Line channels. First-party surfaces are governed by native Managed Environment sharing plus telemetry-drift detection.
- **Optional and conditional.** This solution is not required for every tenant. It applies only where owned custom-web / Direct Line channels exist. The corrected entitlement contract allows a `none` pathway and denies only inside a metered pathway.
- **Reference-gateway-first.** A non-production reference gateway validates the entitlement contract end-to-end before any production deployment is considered. Design validation and customer deployment are deliberately decoupled.
- **Cross-solution columns (reconciled 2026-06-09).** Compliance posture is read from `fsi_caicompliancestate.fsi_risklevel` (`copilot-agent-inventory`, keyed on `fsi_agentid`) and the precomputed per-(agent,user) entitlement decision from `fsi_cbgentitlementmaterialized` (`copilot-billing-governance`: `fsi_decision` / `fsi_pathway` / `fsi_decisionreason`, keyed on `fsi_agentid` + `fsi_userupn`). Re-verify these logical names against live tenant metadata before production use; the `$select` / `$filter` clauses in [templates/apim-eligibility-check.policy.xml](templates/apim-eligibility-check.policy.xml) already target them.
- **Native-control latency boundary.** Managed Environment agent sharing (`bot-*` extended settings) applies with roughly an hour of enforcement latency and governs first-party surfaces. The gateway is the hard, request-time allow/deny for owned channels; the native sharing latency does not apply to the gateway path.

## Documentation

| Document | Purpose |
|---|---|
| [docs/architecture.md](docs/architecture.md) | The two runtime paths (owned-channel gateway vs. first-party native controls) and the control-layer summary |
| [docs/prerequisites.md](docs/prerequisites.md) | Azure, Entra ID, managed-identity, and governance-store prerequisites |
| [docs/apim-gateway-setup.md](docs/apim-gateway-setup.md) | Step-by-step APIM build: instance, named values, policy fragments, managed identity, telemetry sink |
| [docs/dataverse-schema.md](docs/dataverse-schema.md) | The optional `fsi_aegdecisionlog` decision-log table (auto-generated) |

### Scripts and templates

- [`scripts/Test-AgentEligibilityPrecondition.ps1`](scripts/Test-AgentEligibilityPrecondition.ps1) — asserts the Entra-ID-auth + require-sign-in precondition on an agent (explicit or live `bot`-table read).
- [`scripts/create_aeg_dataverse_schema.py`](scripts/create_aeg_dataverse_schema.py) — creates the optional `fsi_aegdecisionlog` table; `--output-docs` regenerates the schema doc.
- [`templates/apim-validate-jwt.policy.xml`](templates/apim-validate-jwt.policy.xml) — APIM `validate-jwt` policy fragment (runs first; 401 on failure).
- [`templates/apim-eligibility-check.policy.xml`](templates/apim-eligibility-check.policy.xml) — APIM allow/deny policy fragment (audience gate + governance-store lookup + entitlement contract; 403 on deny).
- [`templates/decision-log.sample.json`](templates/decision-log.sample.json) — illustrative `fsi_aegdecisionlog` rows.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.
