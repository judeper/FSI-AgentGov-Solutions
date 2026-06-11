# Changelog

All notable changes to the Copilot Billing Governance solution are documented in this
file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- **FNF People-Sweep lens: id-map stem collisions no longer silently drop or mis-attribute
  provisional rows.** `Resolve-FnfPeopleAgentSet` now reconciles each People feature row on a
  UNIQUE per-feature key (CAI's salted `fsi_sourceobjectid`, else `fsi_caiagentfeatureid`) in
  preference to the bare provisional stem `fsi_agentid` (commonly the literal
  `"declarativeAgent"`, which is identical across distinct Toolkit packages). When a single
  id-map key / stem would reconcile more than one distinct feature row to the same Dataverse bot
  GUID, the rows are no longer collapsed to a single survivor -- previously the second row was
  dropped by the de-dup and the first could be scored against the wrong audience. Each colliding
  row is now surfaced as `coverageStatus = Partial` with `coverageGaps += idmap-stem-collision`
  (alongside `manifest-id-unreconciled`), and `summary.idMapStemCollisionCount` reports the count.
  `ConvertTo-FnfIdMap` now rejects a conflicting duplicate key (the same id mapped to two
  different bot GUIDs) instead of last-write-wins. This is required for accurate per-agent
  audience attribution and supports compliance with oversight of Copilot agent reach.
- **FNF People-Sweep lens: a missing or short engine decision file no longer reads as a silent
  "0 blocked".** After the entitlement engine runs, `Invoke-FnfEntitlementScoring` now compares
  the number of decisions written against the number of (agent, user) pairs submitted to the
  engine. If the decision file is absent (for example an ACL or race condition, or a swallowed
  child-process error, since `$ErrorActionPreference = 'Stop'` does not cross the child `pwsh`
  process boundary) or contains fewer decisions than expected, every scored agent now reports
  `coverageStatus = Failed` with `coverageGaps += engine-decisions-missing` and
  `blockedUserCount = null` instead of `0` / `Complete`. `summary.engineDecisionsMissing`,
  `summary.expectedDecisionCount`, and `summary.actualDecisionCount` record the condition. This
  is recommended to avoid under-reporting blocked users when the engine output is incomplete.
- **FNF lens regression tests** (`tests/FnfPeopleSweepReport.Tests.ps1`): added six regression
  tests for the two fixes above -- unique-key reconciliation of stem-sharing rows to distinct
  GUIDs with no mis-attributed audience, stem-collision surfacing (both rows accounted for, never
  first-wins-rest-disappear), conflicting-duplicate-key rejection in `ConvertTo-FnfIdMap`, and the
  engine-decisions-missing guard for both a missing and a short decision file.

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
- **Per-user entitlement resolver** (`scripts/Get-CopilotEntitlement.ps1`): produces the
  engine's per-user inputs from real tenant data — `hasCopilotLicense` by the **paid
  Microsoft 365 Copilot service-plan allowlist** (8 GUIDs, `provisioningStatus = Success`,
  via `licenseDetails` so transitive group-based licenses count) with
  `Bing_Chat_Enterprise` and other confusable plans explicitly **denied**; a
  `/subscribedSkus` tenant SKU dictionary that resolves undocumented Copilot-bearing SKUs
  ("E7", "Copilot Premium") by construction; and PAYG / credit coverage (including an
  "All Users" scope and group transitive membership) mapped to `inCreditScopeGroup`, per
  gated capability. Emits a Find-No-Filter "blocked" lens
  (`isBlocked ⇔ no paid plan AND no applicable PAYG coverage`) plus an engine-ready
  document, and fails **open** on a read error (records the user unresolved, never
  "blocked"). The billing-policy REST schema is unproven, so `-BillingPolicyInputPath` /
  `-BillingPolicy` is preferred over the best-effort live read.
- **Resolver test suite** (`tests/CopilotEntitlement.Tests.ps1`): 20 Pester tests with a
  mocked Graph / billing-policy seam covering the `Bing_Chat_Enterprise` DENY trap, the
  "All Users" PAYG case, transitive group licensing, the unlicensed + no-PAYG block,
  undocumented-SKU-by-construction, fail-open-on-error, per-capability coverage, and an
  end-to-end engine integration (licensed → Allow, unlicensed → Block).
- **Find-No-Filter (FNF) People-Sweep lens** (`scripts/Get-FnfPeopleSweepReport.ps1`):
  an orchestrator that joins the upstream Copilot Agent Inventory (CAI) People-capability
  detection and audience-expansion artifacts with the CBG entitlement resolver and engine
  to produce a per-agent FNF report. Implements three contract seams from the GATE-1
  review: (1) **agent-id keying** that joins on `fsi_agentid` only when
  `fsi_agentrefprovisional = false` (or after an accepted `-IdMapPath` reconciliation),
  surfacing an unreconciled provisional row as `coverageStatus = Partial` (gap
  `manifest-id-unreconciled`) rather than silently joining it to a real agent or dropping
  it; (2) a **field-shape transform** from CAI's `agents[].intendedUsers[].upn` objects to
  the resolver's `intendedUpns[]` string array, with a `createdIn` join from
  `fsi_copilotagent` (`fsi_createdin`) and a Work-IQ-less degradation that passes an empty
  `configuredTier` so the engine uses its `createdIn` pathway fallback; and (3) a
  **whole-tenant** arm that, for an org-wide People-capable agent
  (`fsi_sharedwitheveryone` / `intendedUsers = []`), emits
  `audienceMode = WholeTenant, coverageStatus = Partial` with `blockedUserCount = null`
  instead of a misleading "0 blocked." Adds a per-agent **`coverageStatus`
  (Complete / Partial / Failed)** roll-up with an explicit `coverageGaps[]` vocabulary so
  no gap (provisional id, attestation-pending manifest, partial / failed audience
  resolution, whole-tenant, unresolved entitlement, Work-IQ-less default pathway) hides
  behind a zero count; failed, unresolved, whole-tenant, and unreconciled-provisional
  cases report `blockedUserCount = null` (never a silent `0`). Per-user scoring is
  delegated to `Get-CopilotEntitlement.ps1` and `Invoke-EntitlementEvaluation.ps1` (not
  reimplemented); the blocked set is engine decisions with `fsi_decision = Block`. Emits
  report JSON (not Dataverse rows); managed-identity-first. Supports compliance with
  oversight of Copilot agent reach by surfacing People-capable agents shared with users
  who lack a Copilot entitlement; organizations should verify results against their own
  tenant licensing and policy state.
- **FNF lens test suite** (`tests/FnfPeopleSweepReport.Tests.ps1`): 35 Pester tests with a
  mocked Graph seam (intercepting through the resolver + engine chain) covering each
  contract seam — the provisional-id gate with and without an `-IdMapPath`, the
  `intendedUsers -> intendedUpns` transform regression (asserting a non-empty UPN list
  actually scores so the transform bug cannot regress), the whole-tenant
  `blockedUserCount = null` arm, the Complete / Partial / Failed roll-up, an id-map
  stem-collision regression (unique-key reconciliation, collision surfacing, and
  conflicting-duplicate-key rejection), an engine-decisions-missing regression (a missing or
  short engine decision file marks scored agents Failed, never a silent `0`), plus a happy path
  (a People-capable agent with a blocked user) and a never-silent-zero invariant.
- **FNF samples** (`templates/fnf-people-sweep-report.sample.json`,
  `templates/agent-id-map.sample.json`) and **fixtures** (`tests/fixtures/fnf/`): a
  representative FNF report covering the Complete / Partial / Failed and whole-tenant
  cases, an `-IdMapPath` reconciliation sample, and the CAI capability / audience /
  agent-master / billing-policy artifact fixtures the test suite runs against.
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

### Changed

- **Zero-rating resolved (default) per the June 2026 Microsoft Copilot Studio Licensing
  Guide (footnotes 6 & 7).** `fsi_zeroratingresolved` now defaults `true`, and
  `Invoke-EntitlementEvaluation.ps1 -ZeroRatingResolved` is a `[bool]` defaulting `$true`
  (previously a fail-closed `[switch]`). A Copilot-licensed `mcp-cs` user on a Microsoft
  365 surface under their own identity (`surfaceZeroRated = true`) now resolves to
  **Allow** — included in the Microsoft 365 Copilot User SL, no credit scope required.
  Unlicensed users, non-Microsoft-365 surfaces, and the
  generative-answer-with-tenant-grounding / beyond-fair-use refinements remain
  credit-metered (confirm per tenant). Pass `-ZeroRatingResolved:$false` to revert to the
  conservative fail-closed posture. Updated `entitlement-decision.sample.json` and
  `coverage-gap.sample.json` so the licensed M365-surface `mcp-cs` case shows Allow and
  the blocked / needs-credit-scope illustration moves to a non-Microsoft-365 surface.
- **Billing-policy inventory surfaces user scope + connected surfaces.**
  `Get-BillingPolicyInventory.ps1` now reports each PAYG policy's `Scope`
  (AllUsers / Group / Unknown), `ScopeGroupIds`, and `ConnectedServices`
  (Chat / SharePoint); the schema (`create_cbg_dataverse_schema.py`) gains a
  `fsi_cbg_userscope` option set plus `UserScope` and `AssignedGroupId` columns on
  `fsi_cbgbillingpolicy`, so an operator can see which policies cover all users for which
  capability and the resolver can surface PAYG scope.

### Notes

- **Proposed framework control 2.27 (Consumption-Entitlement Governance)** is
  documented as a cross-repo follow-up for `judeper/FSI-AgentGov`, with an explicit
  rule-out of extending existing controls 2.26 (Entra Agent ID) and 1.18
  (App-Level Authorization). It is intentionally **not** listed in `manifest.yaml`,
  which carries only existing framework control IDs.
- **Zero-rating is RESOLVED (default)** per the June 2026 Microsoft Copilot Studio
  Licensing Guide (footnotes 6 & 7); `fsi_zeroratingresolved` defaults to `true`. The
  generative-answer-with-tenant-grounding and beyond-fair-use refinements remain a
  per-tenant credit-cost caveat.
- **Write APIs are unproven** — credit-policy CRUD, per-agent caps, and hard-stop may
  have no public write API; enforcement degrades to detect-and-alert until confirmed.
- **Upstream dependencies** `copilot-agent-inventory` and `work-iq-usage-detection`
  are built in the same wave; the engine runs on fixture inputs (`-InputPath`) until
  they are catalog-registered. Work IQ GA / consumption-billing switch is
  **June 16 2026**.
