# Changelog

All notable changes to this solution are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- MSCAT "Building Enterprise AI Solutions" Part 2 watch — `scripts/watch_mscat_part2.py`
  (unit-tested in `tests/`) plus repo workflow `.github/workflows/mscat-part2-watch.yml`.
  A weekly poll of the MS Copilot Studio CAT blog opens an issue when Part 2 publishes,
  self-surfacing the deferred early-release-ring env-var schema
  (`create_erv_environment_variables.py`) and Check 4 (`EarlyReleaseReadinessCheck`) live
  probe instead of relying on manual polling. Tracking: JudeSquad #1266 / #1431.

## [0.1.0-preview] - 2026-06-30

### Added

- Initial preview scaffold for pre-promotion resilience validation of Copilot Studio agents,
  mapping controls 2.1, 2.4, 2.8, 1.9 (lifecycle-ops, tier 2, preview).
- Dataverse schema (`create_erv_dataverse_schema.py`): the `fsi_ervalidationresult` table
  (12 columns) plus the `fsi_erv_testtype` and `fsi_erv_teststatus` global option sets, with
  offline `--output-docs` generation of `docs/dataverse-schema.md`.
- `Invoke-EarlyReleaseValidation.ps1` implementing the three offline structural checks:
  - **FallbackCoverageCheck** — every topic that calls a connector/flow has an error-handling
    construct.
  - **ConnectorResilienceCheck** — connection references are per-environment bindable (no
    hard-coded connection id values).
  - **ErrorRecoveryCheck** — a System Fallback topic (and Escalate topic when present) carries a
    non-stub user-facing message.
  - Plus the composite **EarlyReleaseReadinessCheck**, whose live probe is deferred (see Notes).
- `Export-ValidationEvidence.ps1` — queries `fsi_ervalidationresults`, aggregates pass/fail/skipped
  metrics and promotion-readiness, and packages a tamper-evident JSON artifact with a SHA-256
  companion file.
- Pester tests for both PowerShell scripts (`*.Tests.ps1`).
- `create_erv_connection_references.py` for the optional Dataverse/Teams orchestration connectors.
- Documentation: prerequisites, fallback-testing guide, troubleshooting, and the generated
  Dataverse schema reference. Sample templates under `templates/`.

### Notes

- Preview status reflects the deferred 20% that depends on MSCAT "Building Enterprise AI Solutions"
  Part 2: `create_erv_environment_variables.py` (a documented stub) and the
  **EarlyReleaseReadinessCheck** live probe. Until Part 2 publishes the early-release-ring
  environment-config schema, the composite check reports `Skipped` and records
  `fsi_promotionready = false`. The three structural checks are independent of that dependency and
  run today.
- The structural checks are a pre-flight coverage gate, not a runtime fault-injection test. Copilot
  Studio exposes no native connector-failure simulation, so the checks detect missing error
  branches rather than proving an error branch fires correctly at runtime.
- Tracking issue: JudeSquad #1266.
