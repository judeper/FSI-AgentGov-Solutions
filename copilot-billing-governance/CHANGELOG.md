# Changelog

All notable changes to the Copilot Billing Governance solution are documented in this
file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-preview] - 2026-06-09

Initial preview scaffold of the Copilot consumption-billing governance pillar for the
FSI Copilot governance build.

### Added

- **7-entity Dataverse schema** (`scripts/create_cbg_dataverse_schema.py`,
  `--output-docs`): `fsi_cbgbillingpolicy` (PAYG, tenant ceiling 50),
  `fsi_cbgcreditpolicy` (prepaid, tenant ceiling 10), `fsi_cbgentitlement`
  (policy-level rule), `fsi_cbgentitlementmaterialized` (per-(agent, user) decision
  cache with TTL), `fsi_cbgcoveragegap` (per-agent aggregate with a capped UPN
  sample), `fsi_cbgagentcap` (per-agent monthly caps with a detect-and-alert
  fallback), and `fsi_cbgapprovedgrouppolicy` (admission-gated maker / audience /
  billing group registry adopting the hardened ASARD shape). Includes 8 solution
  option sets, one coverage-gap lookup relationship, and managed-identity-first
  authentication via the shared Dataverse client.
- **Switch-on-pathway entitlement contract**
  (`docs/entitlement-contract.md`): classifies the agent pathway first
  (`none` / `mcp-cs` / `mcp-agentbuilder` / `api-direct` / `metered` / `unmapped`),
  with an explicit `none → ALLOW (eligibility N/A)` arm, a bounded metered-only
  `ELSE → block`, a fail-closed `mcp-cs` zero-rating arm, and a
  `unmapped → fail-open-with-anomaly` default. Includes the decision tree,
  pseudocode, per-feature credit-rate table, and the two-policy-object model.
- **Policy inventory script** (`scripts/Get-BillingPolicyInventory.ps1`): reads PAYG
  and credit policy state from the reconciled Dataverse store (or, with
  `-FromPlatform`, the Power Platform billing-policy admin API for PAYG) and reports
  headroom against the 50 / 10 ceilings.
- **Entitlement engine** (`scripts/Invoke-EntitlementEvaluation.ps1`): implements the
  switch-on-pathway contract and the per-agent coverage-gap aggregate (monitor-only),
  with per-feature Copilot credit-rate constants and a configurable cache TTL and
  blocked-UPN sample cap.
- **Documentation**: `docs/architecture.md` (two policy objects, three group layers,
  entitlement engine, coverage-gap, build dependency graph),
  `docs/prerequisites.md` (managed-identity-first auth, least-privilege roles, Graph
  scopes), `docs/dataverse-schema.md` (auto-generated), and
  `docs/flow-configuration.md` (15-minute policy-sync flow and nightly coverage-gap
  flow — build steps only, no exported flow JSON).
- **Samples** (`templates/coverage-gap.sample.json`,
  `templates/entitlement-decision.sample.json`): representative
  `fsi_cbgcoveragegap` and `fsi_cbgentitlementmaterialized` rows covering all five
  decision arms.
- **Manifest** (`manifest.yaml`): catalog metadata for controls 3.5, 1.18, and 1.14;
  tier 2; zones `team` / `enterprise`; `confidential` data classification; `mixed`
  upstream dependency on Copilot Credits consumption billing; dependencies on
  `copilot-agent-inventory` and `work-iq-usage-detection`.

### Notes

- **Proposed framework control 2.27 (Consumption-Entitlement Governance)** is
  documented as a cross-repo follow-up for `judeper/FSI-AgentGov`, with an explicit
  rule-out of extending existing controls 2.26 (Entra Agent ID) and 1.18
  (App-Level Authorization). It is intentionally **not** listed in `manifest.yaml`,
  which carries only existing framework control IDs.
- **Zero-rating is carried as CONFLICTED → fail-closed interim**, pending the
  June 2026 Microsoft Copilot Licensing Guide PDF. `fsi_zeroratingresolved` defaults
  to `false`.
- **Write APIs are unproven** — credit-policy CRUD, per-agent caps, and hard-stop may
  have no public write API; enforcement degrades to detect-and-alert until confirmed.
- **Upstream dependencies** `copilot-agent-inventory` and `work-iq-usage-detection`
  are built in the same wave; the engine runs on fixture inputs (`-InputPath`) until
  they are catalog-registered. Work IQ GA / consumption-billing switch is
  **June 16 2026**.
