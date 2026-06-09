# Architecture

The Agent Eligibility Gateway is one layer in a two-path enforcement composition. A request reaches an agent through exactly one of two paths, and the governing controls differ by path. Understanding which path applies to a given agent is required before deploying — or deciding not to deploy — this gateway.

## Why there are two paths

Custom middleware can only sit in the request path of a channel that the organization fronts itself. **First-party agent surfaces — Microsoft Teams, Microsoft 365 Copilot, and SharePoint — do not expose a middleware insertion point**, so a request to an agent on those surfaces cannot traverse an APIM gateway. As a result:

- **Owned channels** (custom web chat over Direct Line / Web Chat, and Direct Line API integrations) can be fronted by this gateway, which renders a **hard allow/deny at request time**.
- **First-party surfaces** are governed by **native Managed Environment sharing** plus **detective telemetry-drift** detection, which apply after the fact and with latency.

The two paths are complementary. The gateway does not replace native controls, and native controls do not provide the request-time allow/deny that the gateway provides on owned channels.

## Path A — Owned-channel gateway (this solution)

```text
Client app  (owned custom-web / Direct Line channel)
   |
   v
Microsoft Entra ID sign-in
   |  precondition: bot.authenticationmode = Integrated or Custom Azure Active Directory
   |               bot.authenticationtrigger = Always (require users to sign in = ON)
   |  bearer token
   v
Agent Eligibility Gateway  (Azure API Management <inbound>)
   |
   |  1. validate-jwt          tenant OpenID config; audience; issuer; tid claim   --> 401
   |  2. audience / Viewers     caller must be in the agent's Viewers group         --> 403
   |  3. governance-store read  managed identity -> fsi_caicompliancestate + fsi_cbgentitlementmaterialized
   |                            (fsi_risklevel; fsi_decision / fsi_pathway)
   |  4. entitlement contract   switch-on-pathway (see below)                       --> 403 on deny
   |  5. decision telemetry     one structured record per request
   |
   +--> allow --> Agent endpoint  (Copilot Studio / custom agent backend)
   |
   +--> telemetry sink (Event Hub -> Function / Stream Analytics)
           |
           v
        fsi_aegdecisionlog   (per-decision audit, control 3.8)
```

**Decision model (switch-on-pathway).** Eligibility is evaluated only inside a metered pathway:

| Condition | Decision | HTTP |
|---|---|---|
| Token invalid / expired / wrong tenant | Deny | 401 |
| Caller not in the agent's audience / Viewers group | Deny | 403 |
| Agent non-compliant in the governance store | Deny | 403 |
| Pathway `metered` and caller in no eligible cohort | Deny | 403 |
| Pathway `none` | Allow | 200 |
| Pathway unmapped / unknown | Allow (anomaly) | 200 |
| Pathway `mcp-cs` / `mcp-agentbuilder` / `api-direct` | Allow | 200 |

The deny on a metered pathway with no eligible cohort, and the allow on a `none` pathway, together implement the corrected entitlement contract: billing eligibility gates a user **only** where a metered pathway makes eligibility meaningful. An unmapped pathway fails open with an anomaly flag so that a classification defect is surfaced for investigation rather than translated into a user-facing denial.

**Failure posture.** Token problems fail closed at `validate-jwt` (401). The audience gate fails closed (403) — including the groups-overage case where the `groups` claim is omitted for callers in many groups (see [apim-gateway-setup.md](apim-gateway-setup.md) for the managed-identity Graph fallback). Compliance fails closed: a missing governance-store row or a store outage is treated as non-compliant. Cohort lookup on a metered pathway fails closed (no eligible cohort found means deny). These are conservative defaults; confirm them against the customer's risk posture during ratification.

## Path B — First-party native controls + telemetry drift

```text
Client  (Microsoft Teams / Microsoft 365 Copilot / SharePoint)
   |
   v
First-party agent surface
   |  no middleware insertion point -> the gateway is not in this path
   v
Native Managed Environment controls
   |  - agent sharing (bot-* extended settings) governs who the agent is shared with
   |  - audience / Viewers security groups govern chat access
   |  - enforcement applies with roughly an hour of latency
   v
Telemetry  (Microsoft Purview audit, Dataverse, App Insights)
   |
   v
Detective telemetry-drift solutions in this repository
   (for example agent-sharing-access-restriction-detector, scope-drift-monitor)
   -> raise findings after the fact; no request-time allow/deny
```

On this path there is no hard allow/deny at request time. Access is shaped by native sharing and audience configuration, and deviations are caught after the fact by the detective solutions that monitor telemetry. The roughly one-hour enforcement latency of Managed Environment sharing is a property of the native control, not of this gateway.

## Control-layer summary

| Layer | Scope | Timing | What it does | Owner |
|---|---|---|---|---|
| **Agent Eligibility Gateway** (this solution) | Owned custom-web / Direct Line channels | Request time (synchronous) | Hard allow/deny: token validation, audience gate, compliance + entitlement contract, per-decision audit | This solution |
| **Managed Environment agent sharing** (`bot-*` extended settings) | First-party surfaces and platform-wide sharing | ~1 hour enforcement latency | Governs who an agent is shared with and the audience that can chat | Power Platform native |
| **Telemetry-drift detection** | First-party surfaces (and owned, as defence in depth) | After the fact | Detects sharing / scope / access drift from telemetry and raises findings | Sibling detective solutions |

The gateway is the **only** layer in this composition that provides a synchronous, request-time allow/deny, and it does so **only** on owned channels. Everywhere else, governance is the combination of native sharing controls and detective telemetry-drift monitoring. This boundary is the reason the gateway is optional and conditional: a tenant whose agents run only on first-party surfaces has no owned-channel request path for the gateway to sit in.

## Where the gateway reads its inputs

The gateway is a **reader** of governance state, never a writer of it:

| Input | Source table | Owning solution | Logical names (reconciled 2026-06-09) |
|---|---|---|---|
| Agent compliance posture | `fsi_caicompliancestate` | `copilot-agent-inventory` | `fsi_risklevel` (keyed on `fsi_agentid`) |
| Precomputed entitlement decision | `fsi_cbgentitlementmaterialized` | `copilot-billing-governance` | `fsi_decision`, `fsi_pathway`, `fsi_decisionreason` (keyed on `fsi_agentid` + `fsi_userupn`) |
| Audience / Viewers membership | Microsoft Entra ID `groups` claim | Tenant identity | `groups` claim on the validated token |

The optional [`fsi_aegdecisionlog`](dataverse-schema.md) table is the gateway's only **output** to Dataverse, and it is written asynchronously by the telemetry sink, not on the request path. The column logical names for `fsi_copilotagent` and `fsi_cbgentitlementmaterialized` are assumptions to confirm against the sibling solutions' schema scripts before production use.

## Deny-reason vocabulary mapping (CBG → AEG)

The billing engine and the gateway use different deny-reason vocabularies. The materialized decision the gateway reads carries a CBG block reason (`fsi_decisionreason`, option set `fsi_cbg_blockreason`), but the gateway's own audit column is `fsi_denyreason` (option set `fsi_aeg_denyreason`), which is coarser. The telemetry sink applies the mapping below when it lands a record in `fsi_aegdecisionlog`; the verbatim CBG reason is retained in `fsi_rawcontext`, so the precise CBG reason remains available for audit.

| CBG `fsi_cbg_blockreason` | Resulting CBG `fsi_cbg_decision` | AEG `fsi_aeg_denyreason` |
|---|---|---|
| No eligible cohort (100000000) | Block | NotInEligibleCohort (100000004) |
| Missing license (100000001) | Block | NotInEligibleCohort (100000004) |
| Zero-rating unresolved - fail-closed (100000002) | Fail-closed - Zero-rating Unresolved | NotInEligibleCohort (100000004) |
| Not in credit scope (100000003) | Block | NotInEligibleCohort (100000004) |
| Policy cap exceeded (100000004) | Block | NotInEligibleCohort (100000004) |
| Unmapped pathway (100000005) | Fail-open - Anomaly | None (100000000) — allow + anomaly, not a deny |

The gateway's own gates set AEG-native deny reasons directly, with no CBG input: the audience gate sets `OutOfPolicyAudience` and the compliance gate sets `AgentNonCompliant`. Token failures are handled earlier in `aeg-validate-jwt` and surface as 401s (`JwtValidationFailed` / `MissingRequiredClaim`), not as gateway 403s. The compliance read fails closed, so a missing compliance row or a transient governance-store outage currently resolves to `AgentNonCompliant`; the `GovernanceStoreUnavailable` value in the AEG option set is reserved for a sink that chooses to distinguish a store outage from a genuine non-compliance. Because the AEG vocabulary collapses every billing-side denial into `NotInEligibleCohort`, the CBG → AEG mapping is one-directional and lossy by design — consult `fsi_rawcontext` for the precise CBG reason. Confirm the AEG option-set values against [dataverse-schema.md](dataverse-schema.md) before relying on them.

## Reference gateway vs. customer deployment

Architecturally, the reference gateway and a customer deployment are the same APIM policy composition pointed at different backends:

- The **reference gateway** runs in a non-production environment, points at representative test agents, and validates the entitlement contract end-to-end (allow/deny outcomes, anomaly fail-open, decision logging) before any production rollout is considered.
- A **customer deployment** points the same policy fragments at a production owned-channel backend. It is optional and applies only where owned custom-web / Direct Line channels exist.

Keeping the two separate lets the entitlement contract be validated as a design artifact independently of whether — and where — a customer chooses to deploy the gateway in production.
