# Changelog

All notable changes to the Copilot Agent Inventory are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
