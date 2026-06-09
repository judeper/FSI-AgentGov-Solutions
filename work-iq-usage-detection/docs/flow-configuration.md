# Work IQ Usage Detection — Nightly Classify Flow

> **Status:** 0.1.0-preview. These are manual build instructions for a Power
> Automate cloud flow. Per the repository content policy, this solution ships
> **documentation only** — there is no exported flow JSON, connection reference,
> or environment-variable export to import. Build the flow in the Power Automate
> designer following the steps below and adapt names to your environment.

## Purpose

A scheduled nightly flow that computes the canonical four-state Work IQ
observed-usage record for every agent by joining Tier-A configuration with Tier-B
telemetry, then writes `fsi_wiqstate` rows and an `fsi_wiqkpi` rollup. This
supports per-zone Work IQ feature-enablement governance (control 2.24) and usage
reporting (controls 3.2, 2.9). It does not, on its own, satisfy any regulation.

## Authentication

Managed-identity-first. Run the orchestration from an Azure-hosted context (for
example an Azure Automation runbook or Azure Function with a managed identity,
invoked by the flow) so that Dataverse, Defender, Application Insights, and
Purview calls use a managed identity rather than a stored secret. A client secret
is acceptable only as a development fallback.

## Prerequisites

- `copilot-agent-inventory` deployed and `fsi_copilotagent` populated.
- `fsi_wiqstate`, `fsi_wiqkpi`, and the four `fsi_wiq_*` option sets created via
  `python scripts/create_wiq_dataverse_schema.py` (dry-run first).
- Tier-A detector (`scripts/Get-WorkIqConfigState.ps1`) reachable from the
  orchestration host.
- Tier-B queries (`scripts/kql/workiq-tierB-defender.kql`,
  `scripts/kql/workiq-tierB-appinsights.kql`) and, optionally, the Purview audit
  companion collection.

## Flow steps

1. **Trigger — Recurrence.** Schedule once per day (for example 03:00 local).
   Nightly cadence balances freshness against telemetry-ingestion lag.

2. **Initialize run context.**
   - Generate a run GUID (used for `fsi_runid` on every row this run).
   - Capture the scan timestamp in UTC (used for `fsi_scantime`).
   - Read the `WorkIqGa20260616` feature flag. While the flag indicates preview,
     use the preview Work IQ tool identifier (`use-work-iq`); after GA, use the
     GA identifier. Re-validate the tool identifiers and telemetry field paths at
     GA (**2026-06-16**).

3. **Tier-A — configuration.** Invoke `Get-WorkIqConfigState.ps1` (via the
   Automation runbook / Function). It reads `fsi_copilotagent`, samples
   `botcomponent` (component types 18 / 15 / 16) and `aipluginoperation`, and
   returns one object per agent with `configuredTier`, `configEvidence`,
   `configComponentType`, and `createdIn`. **Do not** query a
   `bot.generativeaiconfiguration` column — it does not exist.

4. **Tier-B — telemetry.** Run, in parallel:
   - **Defender** `workiq-tierB-defender.kql` (Advanced Hunting): direct Work IQ
     tool invocations (`ExecuteToolByGateway`). Use a 30-day lookback.
   - **Application Insights** `workiq-tierB-appinsights.kql`: production Work IQ
     invocations (`designMode == "False"` excludes maker test-canvas traffic).
     Use a 7-day lookback for the business-user signal and a 30-day lookback for
     the invoked-30d signal.
   - **Purview** (optional companion): `CopilotInteraction` / `AIPluginOperation`
     records for Work IQ via the audit APIs.

5. **Join and classify.** Join Tier-A and Tier-B on the agent identifier
   (`fsi_agentid`), scoped by environment, and resolve `fsi_observedstatus` using
   the four-state truth table in [`architecture.md`](architecture.md):
   - `none` → **Not configured**.
   - configured + no signal → **Configured-not-observed**.
   - configured + direct Work IQ tool signal → **Observed-invoking**.
   - native-configured + only adjacent connector activity → **Exception-unknown**
     (never Observed-invoking).
   Record the deciding `fsi_telemetrysource`, `fsi_lastobservedat`,
   `fsi_distinctusercount` (count only — no UPNs, to limit PII), and the lookback
   used (`fsi_lookbackdays`).

6. **Upsert `fsi_wiqstate`.** Write one row per agent for this run. Use logical
   names in all OData (for example `fsi_observedstatus`, `fsi_configuredtier`,
   `fsi_invoked30d`, `fsi_invoked7dbybusinessusers`). Set
   `fsi_invoked30d` and `fsi_invoked7dbybusinessusers` from the Tier-B signals.

7. **Compute and upsert `fsi_wiqkpi`.** Aggregate this run into one rollup row
   (optionally one per zone, with Unclassified = tenant-wide):
   - `fsi_configuredcount` (KPI 1), `fsi_invoked30dcount` (KPI 2),
     `fsi_invoked7dbusinessuserscount` (KPI 3).
   - The four-state distribution counts and `fsi_totalagents`,
     `fsi_lookbackdays`.

8. **Alert / report (optional).** Surface the rollup to a Teams channel or the
   compliance dashboard. Highlight new **Exception-unknown** agents and any
   natively-configured agents that remain **Configured-not-observed** beyond an
   expected review window.

## Operational caveats

- **Lookback false negatives.** Low-frequency agents (for example quarterly
  reporting agents) can appear **Configured-not-observed** because their last
  invocation predates the lookback. Treat the invoked KPIs as a floor and widen
  the lookback when reviewing low-frequency agents.
- **Telemetry ingestion lag.** Defender / Application Insights / Purview data can
  lag several hours; the nightly cadence is recommended to allow ingestion to
  settle.
- **Preview connectors.** The Defender `CloudAppEvents` connector is preview for
  some tenants at scaffold time. If it is unavailable, run Tier-B from
  Application Insights and Purview, and record the reduced coverage in
  `fsi_notes`.
