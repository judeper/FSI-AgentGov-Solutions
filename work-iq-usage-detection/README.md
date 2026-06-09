# Work IQ Usage Detection

> **Version:** v0.1.0-preview
> **Status:** Preview
> **Domain:** Monitoring & Analytics · **Tier:** 2
> **Upstream Microsoft dependency:** Preview — Work IQ GA June 16 2026; the use-work-iq capability is still preview at scaffold time. Build GA-ready; the WorkIqGa20260616 feature flag is a short-lived preview-to-GA toggle removed after GA.

Two-tier (configuration + telemetry) detection of Microsoft 365 **Work IQ** usage
by Copilot Studio and Copilot agents, classifying every agent into a canonical
**four-state** observed-usage model for per-zone feature-enablement governance and
usage analytics. This solution helps support — it does not by itself satisfy —
the related controls and regulations.

## Overview

Organizations need to know not just whether agents *can* use Work IQ, but whether
they actually *do*, and by whom. Conflating the two produces misleading
governance signals. Work IQ Usage Detection keeps configuration and telemetry in
two independent tiers and only combines them at a controlled join step:

- **Tier-A (configuration)** — *Can* the agent use Work IQ, and how is it wired?
  Read from Dataverse metadata (`botcomponent`, `aipluginoperation`,
  `bot.configuration`).
- **Tier-B (telemetry)** — *Did* the agent invoke Work IQ at runtime, and who by?
  Read from Microsoft Defender XDR `CloudAppEvents`, Application Insights
  `customEvents`, and Purview audit (`CopilotInteraction`, `AIPluginOperation`).

The join produces one `fsi_wiqstate` row per agent (the canonical four-state) plus
an `fsi_wiqkpi` rollup.

### Two-tier configuration pathways

Tier-A assigns each agent a `configuredTier`:

| `configuredTier` | Meaning |
|------------------|---------|
| `native-mcp-copilot-studio` | Native Work IQ MCP tool identifiers (preview: `use-work-iq`) in `botcomponent` / `aipluginoperation`; keyed on the Azure Resource Graph `createdIn` value from `copilot-agent-inventory`. |
| `native-api-direct` | Work IQ invoked directly through its API. |
| `adjacent` | No native Work IQ tool, but knowledge components (`componenttype = 16`) referencing SharePoint / Microsoft Graph / Microsoft 365 connectors, `botcomponent` table-search, or generative-AI configuration. |
| `none` | None of the above. |

> **Build-time guard:** `bot.generativeaiconfiguration` is **not** a Dataverse
> column. Work IQ configuration is sampled from `botcomponent` component types
> **18 / 15 / 16** (and `bot.configuration` where needed).

### Canonical four-state model

`fsi_wiqstate.fsi_observedstatus` resolves to exactly one of:

1. **Not configured**
2. **Configured-not-observed**
3. **Observed-invoking**
4. **Exception-unknown** — a natively-configured agent whose runtime telemetry
   shows only *adjacent* connector activity (no direct Work IQ tool signal). This
   is never labelled "Observed-invoking".

The full decision logic is the truth table in [`docs/architecture.md`](docs/architecture.md).

### Three KPIs

The `fsi_wiqkpi` rollup reports: **configured**, **invoked-30d**, and
**invoked-7d-by-business-users**, plus the four-state distribution. Because of
lookback windows, low-frequency agents can be a false negative on the invoked
KPIs — treat them as a floor, not an exact count.

## Solution components

```
work-iq-usage-detection/
├── README.md
├── CHANGELOG.md
├── manifest.yaml
├── docs/
│   ├── architecture.md          # Two-tier model, join, four-state truth table
│   ├── prerequisites.md         # Roles, licensing, dependency, auth
│   ├── dataverse-schema.md      # Auto-generated table/column/option-set reference
│   └── flow-configuration.md    # Nightly classify flow (manual build; no JSON)
├── scripts/
│   ├── create_wiq_dataverse_schema.py   # fsi_wiqstate + fsi_wiqkpi + option sets
│   ├── Get-WorkIqConfigState.ps1        # Tier-A configuration detector
│   └── kql/
│       ├── workiq-tierB-defender.kql    # Tier-B: Defender CloudAppEvents
│       └── workiq-tierB-appinsights.kql # Tier-B: Application Insights customEvents
└── templates/
    └── wiqstate.sample.json     # Sample fsi_wiqstate rows (one per state)
```

## Prerequisites

This solution **depends on [`copilot-agent-inventory`](../copilot-agent-inventory/README.md)**
— deploy and populate the `fsi_copilotagent` master first. Work IQ Usage
Detection reads it and does not duplicate it. Roles required include **Power
Platform Admin** (Tier-A reads and writes), **Security Admin** (Defender / Purview
access), and **Log Analytics Reader** (Application Insights). Full details,
licensing, and the managed-identity-first auth model are in
[`docs/prerequisites.md`](docs/prerequisites.md).

## Deployment

```powershell
# 1. Generate the schema documentation (no connection required).
python scripts/create_wiq_dataverse_schema.py --output-docs

# 2. Deploy the Dataverse schema (dry-run first; managed identity preferred).
python scripts/create_wiq_dataverse_schema.py --environment-url "https://org.crm.dynamics.com" --dry-run
python scripts/create_wiq_dataverse_schema.py --environment-url "https://org.crm.dynamics.com"

# 3. Run the Tier-A configuration detector.
. ./scripts/Get-WorkIqConfigState.ps1
Get-WorkIqConfigState -DataverseUrl "https://org.crm.dynamics.com"

# 4. Run the Tier-B queries (Defender Advanced Hunting + Application Insights),
#    then build the nightly classify flow per docs/flow-configuration.md.
```

The nightly flow joins Tier-A and Tier-B, applies the four-state truth table, and
writes `fsi_wiqstate` rows and the `fsi_wiqkpi` rollup. Verify deployment by
confirming one `fsi_wiqstate` row per agent with a populated `fsi_observedstatus`.

## Related Controls

| Control | Relationship |
|---------|-------------|
| [2.24 — Agent Feature Enablement and Restriction Governance](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.24-agent-feature-enablement-and-restriction-governance/) | Primary — detects and classifies Work IQ feature usage per zone. |
| [3.2 — Usage Analytics and Activity Monitoring](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring/) | Primary — invoked-usage KPIs and four-state reporting. |
| [2.9 — Agent Performance Monitoring and Optimization](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization/) | Supporting — runtime invocation telemetry. |

These controls contribute to FINRA Rule 4511 and SEC Rule 17a-3 record-keeping
context and to OCC 2011-12 / Fed SR 11-7 oversight expectations. Implementation
requires organizations to verify their own obligations; no single control
satisfies a regulation in isolation.

## Assumptions and build-time verifications

This preview is built from the Phase 1 verification digest. The following are
**assumptions** to validate against a live tenant before relying on the output:

- **Dependency on `copilot-agent-inventory`.** The agent master `fsi_copilotagent`
  (and its `createdIn` value) is owned upstream; exact column logical names
  resolve from that solution's published schema. (`phase0-pillar2-workiq`)
- **Work IQ GA is 2026-06-16** (not the 17th); `use-work-iq` is still preview at
  scaffold time. The `WorkIqGa20260616` flag is a short-lived preview-to-GA
  toggle; re-validate tool identifiers and telemetry field paths at GA.
  (`phase1-verify-workiq` §4)
- **`bot.generativeaiconfiguration` is not a column.** Tier-A samples
  `botcomponent` component types **18 / 15 / 16** (and `bot.configuration`).
  (`phase1-verify-schema`)
- **Tier-A pathways:** native (MCP tool identifiers in `botcomponent` /
  `aipluginoperation`) vs adjacent (knowledge `componenttype = 16`,
  `botcomponent` table-search, generative-AI config); native-MCP keys on ARG
  `createdIn`. (`phase1-verify-workiq` §4, `phase0-MATRIX-AMENDMENTS`)
- **Tier-B Defender query** uses `CloudAppEvents` with
  `ActionType == "ExecuteToolByGateway"` and a `RawEventData` tool-name match. The
  Defender for Cloud Apps connector is **preview** for some tenants — confirm
  availability. The Tier-A posture companion `AgentsInfo` was renamed from
  `AIAgentsInfo` (cutover **2026-07-01**). (`phase1-verify-workiq` §4)
- **Tier-B Application Insights** excludes maker test-canvas traffic via
  `designMode == "False"`; event-name / dimension paths are JSON-sampling
  assumptions to validate. (`phase1-verify-workiq` §4)
- **Lookback false negatives:** quarterly-use agents can read as
  Configured-not-observed; the invoked KPIs are a floor, not an exact count.

## Documentation

- [Architecture](docs/architecture.md) — two-tier model, join, four-state truth table
- [Prerequisites](docs/prerequisites.md) — roles, licensing, dependency, auth
- [Dataverse Schema](docs/dataverse-schema.md) — tables, columns, option sets
- [Flow Configuration](docs/flow-configuration.md) — nightly classify flow

See the [CHANGELOG](CHANGELOG.md) for version history.

## Cloud scope

This content targets **US commercial-cloud Microsoft 365**. See the repository
[SCOPE.md](../SCOPE.md) for the full cloud-scope statement.

## License

MIT License — See [LICENSE](../LICENSE)
