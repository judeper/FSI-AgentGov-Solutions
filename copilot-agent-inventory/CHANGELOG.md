# Changelog

All notable changes to the Copilot Agent Inventory are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0-preview] - 2026-07-20

### Correction note — 2026-07-20 (post-merge, same version)

- **Integrated scanner command corrected**: `discover_agents.py` integrates
  registry correlation (`--registry-export`, `--columnmap`, `--as-of`) and
  entitlement resolution (`--resolve-entitlement`) as optional post-processing
  inside `scan_all`. The primary command that produces the combined BI-ready
  JSON is:
  ```
  python discover_agents.py --enable-package-api \
    --registry-export <export.xlsx> \
    --columnmap templates/registry-columnmap.sample.json \
    --as-of 2026-07-20T18:00:00Z \
    --resolve-entitlement --output scan.json
  ```
  `import_registry_export.py` and `resolve_owner_entitlement.py` remain
  available as standalone diagnostic tools only. Combined JSON output includes
  `agents[]` enriched with package and owner/entitlement fields, plus two
  summary blocks: `registryCorrelation` (`registryRowCount`, `matched`,
  `unmatchedRegistryRows`, `ambiguousNameSkipped`, `invalidDateWarnings`,
  `status`) and `entitlementResolution` (`ownersConsidered`, `paidCount`,
  `chatOnlyCount`, `unknownCount`, `status`).
- **Persistence framing corrected**: the scanner emits JSON via `--output` and
  does NOT itself write to Dataverse. `docs/flow-configuration.md` updated to
  document the flow persisting `agents[]` into `fsi_copilotagent` (including all
  new package, owner, and entitlement logical fields) before writing the run
  summary. The old framing ("scanner upserts directly via `$batch`") has been
  removed.
- **Evidence field corrected**: `fsi_ownerentitlementevidence` records matched
  **service-plan GUIDs only** — not SKU GUIDs. `templates/package-inventory.sample.json`
  updated: Paid Copilot rows now carry real service-plan GUIDs
  (`3f30311c-6b1e-48a4-ab79-725b469da960` M365_COPILOT_BUSINESS_CHAT for row 1;
  `a62f8878-de10-42f3-b68f-6149a25ceb97` M365_COPILOT_APPS for row 5). The
  previously incorrect SKU GUIDs (`a809996b-...` and `639dec6b-...`) have been
  removed.
- **CLI flag corrections in README and prerequisites**: removed invalid flags
  `--column-map` (correct flag is `--columnmap`); removed importer flags
  `--environment-url` and `--tenant-id` (do not exist); removed resolver flag
  `--environment-url` (does not exist); corrected resolver standalone example
  to require `--upns-file`. Package columns (`fsi_packagetype`,
  `fsi_elementtypes`, `fsi_isblocked`, `fsi_packageversion`, `fsi_assetid`)
  added to sample rows in `package-inventory.sample.json`. Registry column map
  corrected: display-name header alias `synthetic_owner_display` removed from
  `owner_upn` mapping (only UPN-shaped headers may map to `owner_upn`).

Adds a fourth discovery layer — the Microsoft Graph Package Management API
(GA v1.0, application permission `CopilotPackages.Read.All`) — for Agent
Builder catalog discovery, plus temporary owner attribution from the manual
Agent Registry export and owner Copilot entitlement classification feeding a
BI dataset that answers three governance questions: who owns agents, which
agents originate in Agent Builder, and whether the owner holds a Paid
Copilot or Copilot Chat Only license.

### Added

- **Package Management API discovery** (`--enable-package-api` flag in
  `scripts/discover_agents.py`): calls
  `GET https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages?$filter=platform eq 'Microsoft 365 Copilot Agent Builder'`
  under application permission `CopilotPackages.Read.All` (admin-consented).
  Fetches package-level metadata — `id` (`P_...`), `displayName`, `type`,
  `platform`, `publisher`, `version`, `manifestId`, `manifestVersion`,
  `appId`, `availableTo`, `deployedTo`, `supportedHosts[]`, `elementTypes[]` —
  and records new package-only rows (Agent Builder agents with no prior
  inventory match) with `fsi_discoverysource = "Package Management API"`. Defensive `@odata.nextLink`
  paging: truncation is treated as an incomplete scan (GATE-1), never a silent
  empty result. Dry-run honored; 429 backoff reused from the existing scanner.
  The flag defaults to `False` so existing three-layer behavior is unchanged
  when the layer is not activated.
- **Reconciliation**: package rows are joined to existing Agent Builder rows via
  `appId` (Package.appId == `fsi_entraappid`) then `manifestId`. On a match
  the existing row is enriched in-place (no duplicate created);
  `fsi_discoverysource` is updated to `"Reconciled (multi-source)"`. On no
  match a new package-sourced row is created with
  `fsi_discoverysource = "Package Management API"`,
  `fsi_ownerentitlement = "Unknown"`, and
  `fsi_ownermatchconfidence = "Unmatched"`. Package `P_...` ids occupy a
  distinct id space from Copilot Studio bot GUIDs; `reconcile_sources()` is
  guarded against cross-id-space false drift.
- **Agent Registry export importer** (`scripts/import_registry_export.py`):
  reads the manually exported Microsoft 365 admin center agent registry (XLSX
  via `openpyxl` read-only or CSV via stdlib `csv`) and correlates owner UPNs
  with existing `fsi_copilotagent` rows. Column header names are loaded from
  `templates/registry-columnmap.sample.json` (configurable alias map — exact
  headers are confirmed against the lab export; the placeholder names in the
  sample are synthetic). Sets `fsi_ownersource = "Agent Registry Export"`,
  `fsi_ownerasofdatetime` to the export's as-of timestamp (staleness signal),
  and records match confidence. Hard-fails with a header-diff error if required
  canonical fields are missing after alias remapping. SHA-256 of the source
  file is recorded for audit provenance.
- **Owner entitlement resolver** (`scripts/resolve_owner_entitlement.py`):
  classifies each owner UPN as `Paid Copilot`, `Copilot Chat Only`, or
  `Unknown` by invoking
  `copilot-billing-governance/scripts/Get-CopilotEntitlement.ps1` as a
  subprocess (`pwsh -NonInteractive`). Reuses the billing-governance GUID
  allowlist as a single source of truth (the GUID list is not duplicated into
  CAI). Classification: `hasCopilotLicense == true` → Paid Copilot; observed
  `Bing_Chat_Enterprise` deny plan with no paid plan → Copilot Chat Only; all
  other cases (lookup failure, unresolved owner, subprocess error) → Unknown.
  Sets `fsi_ownerentitlementevidence` to matched service-plan GUIDs only — no
  PII or UPNs in the evidence field. Graph token is passed via environment
  variable (not CLI argument) to avoid process-list exposure.
- **Schema additions** (`scripts/create_cai_dataverse_schema.py`): four new
  option sets (`fsi_cai_ownerentitlement`, `fsi_cai_ownersource`,
  `fsi_cai_ownermatchconfidence`, `fsi_cai_packagestatus`) and additive value
  `Package Management API` (100000004) on `fsi_cai_discoverysource`. Twelve
  new columns on `fsi_copilotagent`: `fsi_packageid`, `fsi_publisher`,
  `fsi_supportedhosts`, `fsi_availableto`, `fsi_deployedto`, `fsi_manifestid`,
  `fsi_manifestversion`, `fsi_ownerentitlement`, `fsi_ownerentitlementevidence`,
  `fsi_ownersource`, `fsi_ownermatchconfidence`, `fsi_ownerasofdatetime`. All
  additions are non-breaking (required=False). `docs/dataverse-schema.md`
  regenerated.
- **Sample fixtures**: `templates/registry-columnmap.sample.json` (alias map
  for the registry importer — header names are synthetic placeholders pending
  lab-export confirmation) and `templates/package-inventory.sample.json`
  (BI-ready synthetic dataset with rows covering all three entitlement values
  and Unmatched/stale-owner examples).
- **`openpyxl>=3.1`** added to `scripts/requirements.txt`.
- **Unit tests** (`tests/`): Package API filter build, defensive paging →
  incomplete on truncation, empty-value handling; reconciliation enrich vs
  duplicate (appId match and no-match paths); registry importer XLSX/CSV
  parse, alias remap, missing-required-column hard-fail, stale owner →
  Unknown + low confidence; entitlement resolver: paid plan match, chat-only
  deny-trap, lookup-fail → Unknown; schema logical-name stability; dry-run
  writes nothing; backward-compat (flag off = unchanged three-layer behavior).

### Fixed

- **Layer 4 scope — Agent Builder only:** the Package Management API layer
  discovers `Microsoft 365 Copilot Agent Builder` packages only. Copilot Studio
  agents are intentionally excluded from this layer: existing layers (ARG,
  per-environment Dataverse, and PPAC) already cover Copilot Studio agents, and
  package-to-bot joins are not strong enough to prevent duplicates. Documentation
  and samples updated throughout.
- **`fsi_discoverysource` on enrichment:** enriched existing Agent Builder rows
  receive `fsi_discoverysource = "Reconciled (multi-source)"`.
  `"Package Management API"` is reserved for new package-only rows with no
  prior inventory match.
- **`fsi_ownerentitlementevidence` shape:** the Dataverse memo column stores a
  JSON-stringified flat array of service-plan GUID strings, not a nested object
  array. `templates/package-inventory.sample.json` updated to reflect the
  correct string-value shape.
- **`fsi_ownermatchconfidence` precision:** `"Exact"` is set only when
  `fsi_ownerid` (object GUID) is present; UPN-only rows carry `"Heuristic"`;
  blank owner carries `"Unmatched"`. Sample updated.
- **Owner vs. creator language:** the Package Management API returns no
  `creator` or `createdBy` field. Documentation updated to consistently refer
  to the registry-sourced identity as the agent owner, not the creator.

### Notes

- **Owner data is temporary and may be stale** — `fsi_ownersource = "Agent
  Registry Export"` means owner attribution comes from a point-in-time manual
  export, not a live API. The `fsi_ownerasofdatetime` field signals the as-of
  date; treat owner data as an approximation until a live owner API is
  available. Use `fsi_ownermatchconfidence` to qualify any owner-dependent
  queries.
- **Entitlement may be Unknown** — entitlement classification requires a live
  Graph license lookup against the owner UPN. Any unresolved owner, lookup
  failure, or subprocess error results in `fsi_ownerentitlement = "Unknown"`.
  Downstream BI queries should account for Unknown rows.
- **Package id ≠ bot GUID** — `fsi_packageid` values (`P_...`) are from the
  Package Management API id space and are distinct from Copilot Studio bot
  GUIDs. The best-effort reconciliation join is via `appId` / `manifestId`;
  unmatched package rows receive a `P_...` value as `fsi_agentid` and should
  not be used in bot-GUID-keyed joins.
- **Global commercial cloud only** — the Package Management API and the
  Microsoft Agent 365 license requirement apply to the US commercial Microsoft
  365 cloud. Government L4/L5/DoD (GCC High, DoD) and 21Vianet tenants are not
  supported. Activate `--enable-package-api` only in supported tenants.
- **`pwsh` required** — `resolve_owner_entitlement.py` invokes PowerShell
  Core (`pwsh`) as a subprocess. Confirm `pwsh` is installed in the execution
  environment before running owner entitlement resolution.

## [0.2.0-preview] - 2026-06-12

Adds two FNF-governance extensions that feed the downstream Copilot Billing
Governance (CBG) solution: declarative-agent "People" capability detection and
sharing-audience-to-UPN expansion.

### Added

- **People capability detection** (`scripts/detect_people_capability.py`): a
  manifest-source-agnostic parser that detects the declarative-agent
  `capabilities[].name == "People"` signal (the "Reference org chart and profile
  info" toggle) from `declarativeAgent.json`. Case-sensitive literal match, stable
  across manifest schema v1.5–v1.7, with the optional v1.7 `include_related_content`
  captured (it does not gate detection). Includes an **acquisition-adapter seam**
  with two implemented adapters — `local-package` (app-package directory/`.zip`)
  and `source-repo` (source/CI tree) — plus a clearly-marked `FutureExportAdapter`
  seam for a scalable tenant-export path. Emits `fsi_caiagentfeature` rows of the
  new **People (Org Chart & Profile)** feature type with provenance
  (`fsi_detectionsource`) and a **Declared (Manifest)** confidence marker
  (`fsi_detectionconfidence`); flags the agent id **provisional** when no
  `--id-map` binds the manifest to its Dataverse bot GUID.
- **Audience → UPN expansion** (`scripts/expand_audience_upns.py`): resolves an
  agent's sharing audience (security groups in `fsi_caiauthshare`) to concrete
  member UPNs via Microsoft Graph **transitive** membership
  (`GET /groups/{id}/transitiveMembers`, `GroupMember.Read.All`), flattening nested
  groups and de-duplicating across viewer/editor groups. Flags
  **"Everyone in the organization"** sharing as `wholeTenant` **without enumerating
  the tenant** (configurable `--whole-tenant-cap`), bounds large groups with
  `--max-members-per-group` (truncation flag), honors HTTP 429 Retry-After backoff,
  and surfaces per-group resolution errors as `Partial`/`Failed` status. Emits a
  CBG-shaped `intendedUsers[].upn` artifact and an optional Dataverse write-back of
  **counts/flags only (no UPNs/PII)**.
- **Schema additions** (`scripts/create_cai_dataverse_schema.py`): new
  `fsi_caiagentfeature` columns `fsi_detectionsource`, `fsi_detectionconfidence`
  (picklists), and `fsi_detectiondetail` (memo); new `fsi_caiauthshare` columns
  `fsi_audiencewholetenant`, `fsi_audienceupncount`, `fsi_audiencetruncated`,
  `fsi_audienceresolutionstatus`, and `fsi_audienceresolvedat`. Adds the
  **People (Org Chart & Profile)** value to the `fsi_cai_featuretype` option set
  and two new option sets, `fsi_cai_detectionsource` and `fsi_cai_detectionconfidence`.
  `docs/dataverse-schema.md` regenerated from the schema source of truth.
- **Sample artifacts**: `templates/people-detection.sample.json`,
  `templates/audience-input.sample.json`, and
  `templates/audience-upn-list.sample.json`.
- **Unit tests**: `tests/test_detect_people_capability.py` and
  `tests/test_expand_audience_upns.py`.

### Fixed

- **GATE-1 hardening (accuracy is customer-facing).** Org-wide-shared agents no
  longer resolve to a confidently-empty audience: whole-tenant reach is now a
  per-agent signal (`fsi_caiauthshare.fsi_sharedwitheveryone`, derived from the
  bot `accesscontrolpolicy` during discovery) instead of being mis-inferred from
  the environment-wide `bot-limitSharingMode`; a posture row with no whole-tenant
  signal and no refs is marked `Partial` (never a silent empty). Provisional
  manifest detections are now queryable (`fsi_caiagentfeature.fsi_agentrefprovisional`)
  and no longer collapse on the `(fsi_agentid, fsi_sourceobjectid)` alternate key
  — provisional rows salt `fsi_sourceobjectid` with a stable per-manifest hash.
  The Microsoft Graph token now refreshes near expiry (no 401 on long runs),
  `Retry-After` parsing handles the RFC 7231 HTTP-date format, malformed/unzippable
  manifests increment a `manifestsFailed` counter that surfaces a `Partial` scan,
  and the Dataverse write-back `$filter` escapes single quotes. Adds two schema
  columns (`fsi_sharedwitheveryone`, `fsi_agentrefprovisional`) and a regression
  test per finding; `docs/dataverse-schema.md` regenerated.

### Notes

- **Declared ≠ effective** — the People signal is detected as authored/available
  in the manifest; a v1.7 `user_overrides` block can remove a capability at
  runtime, so the marker is "Declared (Manifest)", not "effective".
- **Provisional agent ids** — declarative manifests carry no Dataverse bot GUID;
  detections without an `--id-map` match are flagged provisional for the
  orchestrator to reconcile before joining CAI/CBG.
- **Privacy** — full UPN lists are emitted only as a transient artifact; Dataverse
  persists audience counts and flags, not member UPNs.

## [0.1.0-preview] - 2026-06-09

Initial preview scaffold of the tier-1 system-of-record for the FSI Copilot
governance build.

### Added

- **Canonical 8-entity Dataverse schema** (`scripts/create_cai_dataverse_schema.py`,
  idempotent, `--output-docs`): `fsi_copilotagent` (agent master),
  `fsi_caienvironment`, `fsi_caiagentfeature` (one row per detected feature),
  `fsi_caiauthshare`, `fsi_caibillingentitlement` (downstream shell),
  `fsi_caiusagesignal`, `fsi_caiworkiqstate` (downstream shell), and
  `fsi_caicompliancestate`. Includes 11 solution-specific option sets, alternate
  keys for idempotent upsert, and managed-identity-first authentication via the
  shared Dataverse client.
- **Three-layer discovery scanner** (`scripts/discover_agents.py`): Azure
  Resource Graph tenant-wide enumeration (`PowerPlatformResources` table,
  `microsoft.copilotstudio/agents`, `SkipToken` paging), per-environment
  Dataverse `bot` / `botcomponent` feature resolution (`parentbotid` lookup,
  `componenttype` 0–19 V1/V2 pairing, six many-to-many relationships), and PPAC
  reconciliation. Includes delta change tracking (`@odata.deltaLink`), OData
  `$batch` writes, bounded ~10-worker concurrency with 429 backoff,
  `incomplete-scan` handling for Lite / Agent Builder agents, and a dry-run mode.
- **Documentation**: `docs/architecture.md` (three-layer discovery, 8-entity
  model, scale engine), `docs/prerequisites.md` (managed-identity-first auth,
  least-privilege roles, token scopes, network endpoints),
  `docs/dataverse-schema.md` (auto-generated reference), and
  `docs/flow-configuration.md` (daily discovery flow build steps — no exported
  flow JSON).
- **Sample record** (`templates/agent-record.sample.json`): a representative
  `fsi_copilotagent` record with `fsi_caiagentfeature` rows (topic, knowledge
  source, custom GPT, tool/plugin, Dataverse search grounding) and a
  `fsi_caicompliancestate` row.
- **Manifest** (`manifest.yaml`): catalog metadata for controls 1.2, 1.7, 2.1,
  and 2.13; tier 1; zones `team` / `enterprise`; `internal` data classification;
  `mixed` upstream dependency on the Power Platform ARG inventory.

### Notes

- **ARA boundary flagged for ratification** — this solution owns the new
  canonical `fsi_copilotagent` entity and does not modify
  `agent-registry-automation`'s legacy `fsi_agentinventory`. Repointing
  `agent-registry-automation` Flow 1 to read `fsi_copilotagent` after
  coverage-parity is an assumption pending ratification (see README).
- **Build-time verifications outstanding (🔎)** — the ARG type live-confirm,
  preview→GA ARG field flips, `botcomponent` JSON payload parsers, the
  `componenttype` ≥20 metadata refresh, and the gen-AI / Work IQ configuration
  location all require a live check before this preview is promoted (see README
  "Assumptions and build-time verifications").
