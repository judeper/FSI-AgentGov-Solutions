# Changelog

All notable changes to the Work IQ Usage Detection solution.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.1.0-preview] — 2026-06-09

### Added

- Initial preview scaffold for two-tier (configuration + telemetry) Work IQ usage
  detection across Copilot Studio and Copilot agents.
- `manifest.yaml` — domain `monitoring-analytics`, tier 2, controls 2.24 / 3.2 /
  2.9, zones team / enterprise, dependency on `copilot-agent-inventory`, and an
  `upstreamDependency` note (Work IQ GA 2026-06-16; `use-work-iq` preview at
  scaffold time; `WorkIqGa20260616` short-lived preview-to-GA flag).
- `scripts/create_wiq_dataverse_schema.py` — creates `fsi_wiqstate` (canonical
  four-state observed-usage record) and `fsi_wiqkpi` (per-run KPI rollup) plus
  four option sets (`fsi_wiq_zone`, `fsi_wiq_configuredtier`,
  `fsi_wiq_observedstatus`, `fsi_wiq_telemetrysource`). Supports `--output-docs`
  (standard-library only) and `--dry-run`; managed-identity-first auth via the
  shared Dataverse client. Reads `fsi_copilotagent` by value and does not
  duplicate the agent master.
- `scripts/Get-WorkIqConfigState.ps1` — Tier-A configuration detector skeleton.
  Samples `botcomponent` component types 18 / 15 / 16 and `aipluginoperation` to
  classify `configuredTier` (`NativeMcpCopilotStudio` / `NativeApiDirect` /
  `Adjacent` / `NotConfigured`); native-MCP keys on the Azure Resource Graph `createdIn`
  value. Includes the build-time guard that `bot.generativeaiconfiguration` is
  not a Dataverse column.
- `scripts/kql/workiq-tierB-defender.kql` — Tier-B telemetry query over Defender
  XDR `CloudAppEvents` (`ExecuteToolByGateway`), parameterized and commented, with
  an `AgentsInfo` / `AgentToolsDetails` posture companion (note: `AgentsInfo` was
  renamed from `AIAgentsInfo`, cutover 2026-07-01).
- `scripts/kql/workiq-tierB-appinsights.kql` — Tier-B telemetry query over
  Application Insights `customEvents` / `AppEvents`, excluding maker test-canvas
  traffic (`designMode == "False"`), parameterized for the 7-day business-user
  KPI window.
- `templates/wiqstate.sample.json` — sample `fsi_wiqstate` rows, one per canonical
  state, keyed on Dataverse logical names.
- Documentation: `README.md`, `docs/architecture.md` (two-tier model, the
  configuration ↔ telemetry join, and the four-state truth table),
  `docs/prerequisites.md`, `docs/dataverse-schema.md` (auto-generated), and
  `docs/flow-configuration.md` (nightly classify flow — documentation only, no
  exported flow JSON).

### Notes

- Preview status reflects the upstream Work IQ dependency. Several Tier-A
  component-type labels and Tier-B telemetry field paths are build-time
  assumptions from the Phase 1 verification digest and are recommended to be
  re-validated against a live tenant and at Work IQ GA.
- This solution helps support per-zone Work IQ feature-enablement governance and
  usage reporting; it does not by itself satisfy any regulation.

[0.1.0-preview]: https://github.com/judeper/FSI-AgentGov-Solutions/releases/tag/work-iq-usage-detection-v0.1.0-preview
