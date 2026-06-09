# Changelog

All notable changes to the Copilot Agent Inventory are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
