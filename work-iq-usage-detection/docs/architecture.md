# Work IQ Usage Detection — Architecture

> **Status:** 0.1.0-preview. Several details below are build-time assumptions
> drawn from the Phase 1 verification digest (`phase1-verify-workiq`,
> `phase1-verify-schema`) and are flagged where they require validation against a
> live tenant. This document describes design intent; it does not assert any
> regulatory outcome on its own.

## Two-tier model (never conflate configured vs invoked)

Work IQ usage is detected in two independent tiers that are computed separately
and only combined at the join step. Keeping them separate is the core design
rule: a configuration signal is **not** an invocation, and an invocation signal
is **not** a configuration.

| Tier | Question | Source | Producer |
|------|----------|--------|----------|
| **Tier-A (configuration)** | *Can* this agent use Work IQ, and how is it wired? | Dataverse metadata (`botcomponent`, `aipluginoperation`, `bot.configuration`) | `scripts/Get-WorkIqConfigState.ps1` |
| **Tier-B (telemetry)** | *Did* this agent invoke Work IQ at runtime, and who by? | Defender `CloudAppEvents`, Application Insights `customEvents`, Purview audit | `scripts/kql/workiq-tierB-*.kql` + Purview audit collection |

### Tier-A: configuration pathways

`Get-WorkIqConfigState.ps1` reads the agent master `fsi_copilotagent` (owned by
`copilot-agent-inventory` — not duplicated here) and samples per-environment
Dataverse metadata to assign a `configuredTier`:

- **`native-mcp-copilot-studio`** — Work IQ MCP tool identifiers (preview:
  `use-work-iq`) present in `botcomponent` / `aipluginoperation`. The native-MCP
  pathway **keys on the Azure Resource Graph `createdIn` value** supplied by
  `copilot-agent-inventory`.
- **`native-api-direct`** — Work IQ invoked directly through its API rather than
  via Copilot Studio authoring.
- **`adjacent`** — no native Work IQ tool, but knowledge components
  (`componenttype = 16`) referencing SharePoint / Microsoft Graph / Microsoft 365
  connectors, `botcomponent` table-search (`dvtablesearch`), or generative-AI
  configuration are present.
- **`none`** — none of the above.

> **Build-time guard (verified):** `bot.generativeaiconfiguration` is **not** a
> real Dataverse column. Work IQ configuration is sampled from `botcomponent`
> component types **18 / 15 / 16** (16 = knowledge source; 15 and 18 are the
> generative / config-bearing component types) and, where needed,
> `bot.configuration`. Do not query a `generativeaiconfiguration` column.

### Tier-B: telemetry sources

| Source | Signal | Notes |
|--------|--------|-------|
| Defender XDR `CloudAppEvents` | `ActionType == "ExecuteToolByGateway"` and `RawEventData` contains the Work IQ tool token | Requires Defender for Cloud Apps connected to Defender XDR; connector is preview for some tenants at scaffold time. |
| Application Insights `customEvents` / `AppEvents` | Work IQ tool token in event name / dimensions, **production traffic only** (`designMode == "False"` excludes maker test-canvas traffic) | Copilot Studio telemetry per agent. |
| Purview audit | `CopilotInteraction`, `AIPluginOperation*` records for Work IQ | Collected via the Purview / Microsoft Graph audit APIs in the nightly flow. |

> **Tier-A posture companion in Defender:** configured agent tools also surface in
> **`AgentsInfo`** (renamed from `AIAgentsInfo`; cutover **2026-07-01**) joined to
> **`AgentToolsDetails`**. Use this only to corroborate Tier-A configuration —
> never to assert an invocation.

## The configuration ↔ telemetry join

The nightly classify flow joins Tier-A and Tier-B per agent:

- **Join key:** agent identifier (`fsi_agentid`, sourced from `fsi_copilotagent`),
  scoped by environment. Defender / App Insights / Purview signals are attributed
  to the agent via their respective agent/bot identifiers.
- **Lookback windows:** 30 days for the "invoked-30d" signal; 7 days for the
  business-user signal. Lookback is recorded on each row (`fsi_lookbackdays`).
- **Output:** one `fsi_wiqstate` row per agent per run, plus an `fsi_wiqkpi`
  rollup row.

### Four-state truth table

`fsi_wiqstate.fsi_observedstatus` is resolved from the join as follows:

| Tier-A `configuredTier` | Tier-B signal in lookback | `observedStatus` | Rationale |
|-------------------------|---------------------------|------------------|-----------|
| `none` | any | **Not configured** | No Work IQ configuration present. |
| `native-mcp` / `native-api` / `adjacent` | no signal | **Configured-not-observed** | Configured but not seen invoking in the lookback window (see false-negative risk). |
| any configured tier | **direct** Work IQ tool invocation (Defender `ExecuteToolByGateway` for the Work IQ tool, App Insights Work IQ event, or Purview `AIPluginOperation` for Work IQ) | **Observed-invoking** | Runtime invocation confirmed. |
| `native-mcp` / `native-api` | telemetry present, but **only adjacent** connector activity (SharePoint / Graph), no direct Work IQ tool signal | **Exception-unknown** | Activity is present but cannot be attributed to Work IQ; classify Exception-unknown, **never** Observed-invoking. |

Notes:

- An `adjacent`-configured agent reaches **Observed-invoking** only on a direct
  Work IQ tool signal; otherwise it stays **Configured-not-observed**.
- **Exception-unknown** is reserved for the dangerous case: a natively-configured
  agent with runtime activity that cannot be confirmed as a Work IQ invocation.
  Labelling it "Observed" would over-count; labelling it "Configured-not-observed"
  would imply no activity. Exception-unknown is the honest middle state.

## KPIs

The `fsi_wiqkpi` rollup reports three headline KPIs plus the four-state
distribution:

1. **Configured** — agents with Work IQ configured (any tier).
2. **Invoked-30d** — agents observed invoking Work IQ within 30 days.
3. **Invoked-7d-by-business-users** — agents invoked within 7 days by business
   (non-maker, non-test) users.

> **Lookback false-negative risk:** agents that use Work IQ only occasionally
> (for example, quarterly reporting agents) may show as **Configured-not-observed**
> simply because their last invocation predates the lookback window. Treat the
> invoked KPIs as a floor, not an exact count, and lengthen the lookback when
> evaluating low-frequency agents.

## GA timing and the feature flag

Work IQ reaches general availability on **2026-06-16**. The `use-work-iq`
capability is still preview at scaffold time, so the solution is built GA-ready
and gates preview-specific behaviour behind a short-lived feature flag,
`WorkIqGa20260616`. The flag is a preview-to-GA toggle and is expected to be
removed after GA; the Work IQ tool identifiers and telemetry field paths should
be re-validated at that point.
