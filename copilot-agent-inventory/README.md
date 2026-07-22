---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P2, P4]
applicable_drivers:
  - ai_governance
coe_function: govern
---
# Copilot Agent Inventory

> **Version:** v0.4.0-preview
> **Status:** Preview
> **Validated against framework version:** v1.6.0
> **Upstream Microsoft dependency:** Mixed — ARG Power Platform Inventory GA Mar 31 2026; Package Management API GA v1.0 (application CopilotPackages.Read.All); several agent-specific ARG fields (isManaged, channels, authentication, capabilitiesCounts, powerPlatformConnectors) are still preview.
> **Last Verified:** 2026-07-21

Tenant-wide discovery and a canonical Dataverse **system-of-record** for every
Copilot Studio and Microsoft 365 Copilot Agent Builder agent. Copilot Agent
Inventory (CAI) is the tier-1 foundation that downstream FSI governance solutions
read from, rather than each re-scanning the platform. This solution targets the
**US commercial Microsoft 365 / Power Platform cloud**.

## Overview

CAI composes a **four-layer discovery** (Azure Resource Graph → per-environment
Dataverse → PPAC reconciliation → Package Management API) and normalizes the
result into nine Dataverse tables. A complete, current agent inventory is
required for agent registry control 1.2 and supports compliance with the
record-keeping expectations of FINRA Rule 4511 and SEC Rule 17a-3/17a-4 (a
documented inventory is a prerequisite for the records those rules require).
The fourth layer — the Microsoft Graph **Package Management API** (GA v1.0,
application `CopilotPackages.Read.All`) — enriches Agent Builder packages and is
selected by a **license-aware Agent 365 mode** (`--agent365 present|absent|auto`,
default `absent`) rather than a bare on/off flag, so a *deferred* or
*not-detected* Agent Builder catalog is never mistaken for an authoritative
absence of Agent Builder agents. Alongside it, temporary owner attribution from
the manual Agent Registry export and owner Copilot entitlement classification
feed a BI dataset that answers three governance questions: who owns agents, which
agents originate in Agent Builder, and whether the owner holds a Paid Copilot or
Copilot Chat Only license. Each run persists exactly one `fsi_caiscanrun` row
carrying the Agent 365 resolution and coverage-scope contract. The inventory also
provides the agent dimension that management and reporting solutions join against.

Unlike `agent-registry-automation` (which operates a registration and approval
workflow over its legacy `fsi_agentinventory` table), CAI owns the **canonical
discovery store** `fsi_copilotagent` and is built for tenant scale (~2,000
agents) with delta change tracking and batched writes. See
[ARA boundary](#ara-boundary-flagged-for-ratification) below.

## Architecture

Full detail in [docs/architecture.md](docs/architecture.md). In summary:

**Four-layer discovery**

1. **Azure Resource Graph (ARG)** — tenant-wide enumeration from the dedicated
   `PowerPlatformResources` table (resource type
   `microsoft.copilotstudio/agents`), via
   `POST {PowerPlatformAPI}/resourcequery/resources/query?api-version=2024-10-01`
   with `SkipToken` paging. The `createdIn` field disambiguates Copilot Studio
   vs Agent Builder agents.
2. **Per-environment Dataverse** — `bot` + `botcomponent` reads to enumerate
   features. The `botcomponent` → `bot` lookup is `parentbotid`
   (`_parentbotid_value`); `componenttype` codes 0–19 are matched as V1/V2 pairs;
   six many-to-many relationships resolve tools, connectors, flows, grounding,
   and AI models.
3. **PPAC reconciliation** — cross-checks ARG against the Dataverse scan and
   records coverage gaps so they are auditable rather than silent.
4. **Package Management API** (Agent Builder catalog) — selected by the
   license-aware **Agent 365 mode** (`--agent365 present|absent|auto`, env
   `CAI_AGENT365`, default `absent`; the deprecated `--enable-package-api` flag
   is a one-release alias for `--agent365 present`). When attempted it calls
   `GET https://graph.microsoft.com/v1.0/copilot/admin/catalog/packages?$filter=platform eq 'Microsoft 365 Copilot Agent Builder'`
   under application permission `CopilotPackages.Read.All` (admin-consented,
   US commercial Microsoft 365 cloud) with a Microsoft Agent 365 license.
   Discovers `Microsoft 365 Copilot Agent Builder` packages only (Copilot Studio
   is intentionally excluded: existing layers already cover it, and
   package-to-bot joins are not strong enough to prevent duplicates). Returns
   package-level metadata (`id` as `P_...`, `displayName`, `publisher`, `appId`,
   `manifestId`, `supportedHosts`, etc.) for Agent Builder packages — **no owner,
   creator, or created-date field**. Enriches existing Agent Builder rows via
   `appId` / `manifestId` (setting `fsi_discoverysource = "Reconciled
   (multi-source)"`); unmatched packages create new rows keyed on the `P_...` id
   (`fsi_discoverysource = "Package Management API"`). Package ids are a distinct
   id space from bot GUIDs — see
   [Reconciliation limitation](docs/architecture.md#reconciliation-limitation).
   The run records the outcome as `summary.agent365` (resolved state
   Present / Absent / NotDetected / Inconclusive; layer status Full / Deferred /
   Unsupported / Partial / Failed / Dry Run) and `summary.coverageScope`. A
   **Deferred or NotDetected Layer 4 never means zero Agent Builder agents** —
   those agents are still discovered by Layers 1–2 via `createdIn`. API errors
   (`401` / `403` / `404` / `429` / `5xx`) are typed as Partial / Failed /
   Unsupported and are **never** read as "no license" or absence. See
   [Agent 365 mode selection](docs/architecture.md#agent-365-mode-selection-license-aware-layer-4).

**9-entity model** (logical names): `fsi_copilotagent` (master),
`fsi_caienvironment`, `fsi_caiagentfeature` (one row per detected feature),
`fsi_caiauthshare`, `fsi_caibillingentitlement` (downstream shell),
`fsi_caiusagesignal`, `fsi_caiworkiqstate` (downstream shell),
`fsi_caicompliancestate`, `fsi_caiscanrun` (one row per scan run — timing,
status, Agent 365 resolution, and coverage scope).

**Scale engine** — delta change tracking (`@odata.deltaLink`), OData `$batch`
writes, bounded ~10-worker concurrency with 429 backoff, and usage aggregated at
source. Lite / Agent Builder agents are recorded as `incomplete-scan` because no
public API returns their full definition.

## Solution Components

```
copilot-agent-inventory/
├── README.md
├── CHANGELOG.md
├── manifest.yaml
├── docs/
│   ├── architecture.md
│   ├── prerequisites.md
│   ├── dataverse-schema.md        # auto-generated — do not hand-edit
│   └── flow-configuration.md
├── scripts/
│   ├── create_cai_dataverse_schema.py   # 9-entity schema, idempotent, --output-docs
│   ├── discover_agents.py               # four-layer discovery scanner (--agent365 present|absent|auto)
│   ├── import_registry_export.py        # Agent Registry XLSX/CSV owner importer
│   ├── resolve_owner_entitlement.py     # owner Copilot entitlement classifier (via CBG PS1)
│   ├── detect_people_capability.py      # declarative-agent People capability (manifest)
│   ├── expand_audience_upns.py          # sharing audience -> member UPNs (Graph transitive)
│   └── requirements.txt
└── templates/
    ├── agent-record.sample.json         # sample fsi_copilotagent + feature rows
    ├── people-detection.sample.json     # sample People-capability detection artifact
    ├── audience-input.sample.json       # sample sharing posture (expand input)
    ├── audience-upn-list.sample.json    # sample CBG-shaped intendedUsers artifact
    ├── package-inventory.sample.json    # BI-ready sample: Package API + owner + entitlement
    └── registry-columnmap.sample.json   # alias map for registry XLSX importer
```

## Quick Start

```bash
# 1. Install Python dependencies
pip install -r scripts/requirements.txt

# 2. Deploy the Dataverse schema (preview first — reads hit the live tenant, no writes)
python scripts/create_cai_dataverse_schema.py \
    --environment-url https://governance.crm.dynamics.com \
    --tenant-id <your-tenant-id> --interactive --dry-run

python scripts/create_cai_dataverse_schema.py \
    --environment-url https://governance.crm.dynamics.com \
    --tenant-id <your-tenant-id> --interactive
```

```bash
# 3. Run the discovery scanner in the default `absent` mode — Layer 4 deferred
#    (dry-run first — no Dataverse writes)
python scripts/discover_agents.py \
    --tenant-id <your-tenant-id> --dry-run --output scan.json

# 4. Production default-mode scan — Layer 4 deferred (managed identity preferred)
python scripts/discover_agents.py \
    --tenant-id <your-tenant-id> --auth-mode managed-identity

# 5. Full integrated scan — Package API + registry owner attribution + entitlement
#
#    Produces a combined BI-ready JSON (--output). The scanner emits JSON and
#    does NOT itself write to Dataverse; persistence is handled by the Power
#    Automate flow documented in docs/flow-configuration.md.
#
#    Layer 4 is selected by the license-aware Agent 365 mode:
#      --agent365 present  attempt the Package API directly
#      --agent365 auto     probe Graph subscribedSkus, then attempt if detected
#      --agent365 absent   (default) skip the probe and the API; mark Layer 4
#                          Deferred — this is NOT zero Agent Builder agents
#    (`--enable-package-api` is a one-release deprecated alias for
#    `--agent365 present`.) The mode may also be set via the CAI_AGENT365
#    environment variable; precedence is explicit CLI > env > alias > default.
#
#    Requirements for present/auto: Microsoft Agent 365 license;
#    CopilotPackages.Read.All application permission (US commercial Microsoft 365
#    cloud); pwsh for entitlement resolution.
#
#    Edit templates/registry-columnmap.sample.json to declare your XLSX column
#    headers before running. Exact native headers in the M365 admin center are
#    unverified; use the alias map to declare the actual header names.
#
#    Combined output includes: agents[] enriched with package, owner, and
#    entitlement fields; summary.agent365 (Agent 365 resolution) and
#    summary.coverageScope (per-layer coverage); registryCorrelation summary
#    (registryRowCount, matched, unmatchedRegistryRows, ambiguousNameSkipped,
#    invalidDateWarnings, status); entitlementResolution summary
#    (ownersConsidered, paidCount, chatOnlyCount, unknownCount, status).
python scripts/discover_agents.py \
    --auth-mode managed-identity \
    --tenant-id <your-tenant-id> \
    --agent365 present \
    --registry-export registry-export.xlsx \
    --columnmap templates/registry-columnmap.sample.json \
    --as-of 2026-07-21T18:00:00Z \
    --resolve-entitlement \
    --output scan.json
```

### Standalone diagnostic tools

The registry importer and entitlement resolver can be run independently to
validate column mapping or troubleshoot entitlement classification. They do
not enrich agents or write to Dataverse.

```bash
# Validate registry export column mapping and row parsing (diagnostic only)
python scripts/import_registry_export.py \
    --input registry-export.xlsx \
    --columnmap templates/registry-columnmap.sample.json \
    --as-of 2026-07-21T18:00:00Z \
    --output rows.json

# Resolve Copilot entitlement for a list of owner UPNs (diagnostic only)
#    Requires pwsh + copilot-billing-governance/scripts/Get-CopilotEntitlement.ps1
python scripts/resolve_owner_entitlement.py \
    --upns-file upns.json \
    --ps1-path ../../copilot-billing-governance/scripts/Get-CopilotEntitlement.ps1 \
    --output ent.json
```

```bash
# Detect the declarative-agent "People" capability from manifests
#    (source-repo tree or local app-package directory/zip; --dry-run plans only)
python scripts/detect_people_capability.py \
    --source source-repo --path ../my-agent-repo \
    --id-map ./agent-id-map.json --output people.json

# Expand each agent's sharing audience to member UPNs (CBG input)
#    --dry-run resolves nothing over the network
python scripts/expand_audience_upns.py \
    --input authshare.json --auth-mode managed-identity \
    --output intended-users.json
```

## Package API, Owner Attribution, and Entitlement BI Dataset

The Layer 4 Package Management API, registry importer, and entitlement resolver
together populate a BI-ready slice of `fsi_copilotagent` that answers three
governance questions:

| Question | Key columns |
|----------|-------------|
| Who owns agents? | `fsi_ownerupn`, `fsi_ownerid`, `fsi_ownersource`, `fsi_ownermatchconfidence`, `fsi_ownerasofdatetime` |
| Which agents were created in Agent Builder? | `fsi_createdin = "Microsoft 365 Copilot Agent Builder"` |
| Is the owner a paid Copilot user or Copilot Chat only? | `fsi_ownerentitlement`, `fsi_ownerentitlementevidence` |

See `templates/package-inventory.sample.json` for a synthetic Contoso dataset
illustrating all three entitlement values, stale-owner examples, and Unmatched
confidence rows.

**Owner data is temporary and may be stale.** `fsi_ownersource = "Agent Registry
Export"` means owner attribution comes from a point-in-time manual export, not
a live API. Check `fsi_ownerasofdatetime` to assess staleness, and qualify any
owner-dependent report with `fsi_ownermatchconfidence`.

**Entitlement may be Unknown.** Any unresolved owner, Graph lookup failure, or
`pwsh` subprocess error sets `fsi_ownerentitlement = "Unknown"`. Downstream BI
queries should filter or flag Unknown rows rather than treating them as
authoritative negatives.

**Package id ≠ bot GUID.** `fsi_packageid` values (`P_...`) are distinct from
Copilot Studio bot GUIDs. Best-effort reconciliation joins on `appId` /
`manifestId`; unmatched rows carry `fsi_ownermatchconfidence = "Unmatched"` and
should not participate in bot-GUID-keyed joins.

## People capability & audience expansion (FNF)

Two FNF-governance extensions augment the core inventory. Both emit transient
JSON artifacts (the system-of-record stays in Dataverse) and supply input to the
downstream Copilot Billing Governance (CBG) solution.

**People capability detection (`detect_people_capability.py`).** The "Reference
org chart and profile info" toggle is the declarative-agent manifest entry
`capabilities[].name == "People"` (a case-sensitive literal, stable across
manifest schema v1.5–v1.7; the optional v1.7 `include_related_content` is
captured but does not gate detection). This signal lives in `declarativeAgent.json`
inside the agent app package — **not** in the Dataverse `bot`/`botcomponent`
definition and not in any public API for deployed agents — so it is parsed from
manifests via a **manifest-source-agnostic** parser behind an acquisition-adapter
seam:

- `--source local-package` — a local app-package directory or `.zip` (reads
  `manifest.json` → `copilotAgents.declarativeAgents[]` → `declarativeAgent.json`).
- `--source source-repo` — a source/CI repository tree (Toolkit-built LOB agents).
- A clearly-marked `FutureExportAdapter` seam is reserved for a scalable
  tenant-export path (a sibling spike is resolving whether one exists); it raises
  `NotImplementedError` rather than silently returning nothing.

Each hit is recorded as a `fsi_caiagentfeature` row of feature type
**People (Org Chart & Profile)** with provenance (`fsi_detectionsource`) and a
**Declared (Manifest)** confidence marker (`fsi_detectionconfidence`). "Declared"
means authored/available in the manifest; a v1.7 `user_overrides` block can remove
a capability at runtime, so declared does not equate to effective. Declarative
manifests carry no Dataverse bot GUID, so without an `--id-map` entry the agent id
is flagged **provisional** and a warning is logged for the orchestrator to
reconcile before joining CAI/CBG.

**Audience → UPN expansion (`expand_audience_upns.py`).** CBG consumes a per-agent
`intendedUsers[]` UPN list, but `fsi_caiauthshare` records the sharing audience as
security-group references. This script expands those groups to member UPNs via
Microsoft Graph **transitive** membership (`GET /groups/{id}/transitiveMembers`,
permission `GroupMember.Read.All`), which flattens **nested groups** automatically,
and de-duplicates across overlapping viewer/editor groups. Defensive handling:

- **"Everyone in the organization"** sharing is flagged `wholeTenant`; the tenant
  is **never enumerated** (a configurable `--whole-tenant-cap` is recorded for the
  consumer, default `0`).
- **`--max-members-per-group`** bounds very large groups and sets a `truncated`
  flag so a partial list is never mistaken for a complete one.
- **HTTP 429 throttling** uses Retry-After-aware backoff; a group that cannot be
  read records a per-group error and the agent status becomes `Partial`/`Failed`
  rather than silently dropping members.
- Only `intendedUsers[].upn` is produced (per-user license/cohort flags are
  separate downstream gaps). The Dataverse write-back carries **counts and flags
  only — no UPNs/PII** — on the `fsi_caiauthshare` audience columns.

Both scripts are **managed-identity-first**, accept `--dry-run`, and support
compliance with the audience-scoping and data-minimization expectations the FNF
deliverable depends on.

## Configuration Placeholders

| Placeholder | Replace With |
|------------|-------------|
| `{{TENANT_DOMAIN}}` | Your tenant domain (e.g., `contoso.onmicrosoft.com`) |
| `{{AZURE_SUBSCRIPTION}}` | Azure subscription ID for Automation |
| `{{RESOURCE_GROUP}}` | Resource group for the Automation account |
| `{{AUTOMATION_ACCOUNT}}` | Azure Automation account name |
| `{{TEAMS_GROUP_ID}}` | Microsoft Teams group (team) GUID (optional) |
| `{{TEAMS_CHANNEL_ID}}` | Microsoft Teams channel GUID (optional) |

## Related Controls

| Control | Relationship |
|---------|-------------|
| [1.2 — Agent Registry and Integrated Apps Management](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.2-agent-registry-and-integrated-apps-management/) | Primary — provides the canonical discovery inventory the registry depends on |
| [1.7 — Comprehensive Audit Logging and Compliance](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance/) | Supporting — durable scan-run records support audit-trail evidence |
| [2.1 — Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.1-managed-environments/) | Dependency — environment dimension and zone classification source |
| [2.13 — Documentation and Record-Keeping](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.13-documentation-and-record-keeping/) | Primary — the inventory is the system-of-record for agent documentation |

## Upstream Dependency

Discovery depends on the Power Platform ARG inventory, whose status is **mixed**:
the inventory/PPAC capability reached GA on **March 31 2026**, but several
agent-specific ARG fields remain in **preview** and must be re-pulled at build
time. This preview release is built GA-ready while those fields are confirmed
live.

## Assumptions and build-time verifications

This preview bakes in verified build-truth from `phase1-VERIFICATION-DIGEST.md`
(§2 discovery, §3 schema) and `phase1-verify-discovery.md` /
`phase1-verify-schema.md`. Tags follow the digest notation: **✅ verified**,
**🔎 unverified — live-check at build**, **⚠️ conflicted**.

**Verified and applied (✅)**

- ARG inventory lives in the dedicated **`PowerPlatformResources`** table, **not**
  `resources`; resource type `microsoft.copilotstudio/agents`; query via
  `POST {PowerPlatformAPI}/resourcequery/resources/query?api-version=2024-10-01`
  with `SkipToken` paging.
- `botcomponent` → `bot` parent lookup is **`parentbotid` (`_parentbotid_value`)**,
  not `_botid_value`.
- `componenttype` ranges **0–19** with V1/V2 pairs (Topic `{0,9}`, Skill `{1,13}`,
  Bot entity `{3,11}`, Bot variable `{2,12}`, Bot translations `{10}`); the six
  M:M relationships are confirmed.
- **`bot.generativeaiconfiguration` is not a real column** — gen-AI / Work IQ
  config is resolved by live sampling of `botcomponent` types 18/15/16 or
  `bot.configuration`, not assumed.
- Lite / Agent Builder agents are correctly recorded as `incomplete-scan`.

**Requires a live check before promotion (🔎)**

- Confirm `microsoft.copilotstudio/agents` resolves via `az graph query` (the
  type is absent from the standard ARG supported-types reference).
- Re-pull the preview→GA ARG fields (`isManaged`, `channels`, `authentication`,
  `capabilitiesCounts`, `powerPlatformConnectors[]`).
- Derive parsers for the undocumented `botcomponent.data` / `botcomponent.content`
  JSON payloads by sampling ~50 pilot agents; fail open with telemetry on
  unrecognized keys.
- Refresh `botcomponent_componenttype` via `GlobalOptionSetDefinitions` to catch
  any value ≥20 added since the reference snapshot.
- Resolve where gen-AI / Work IQ configuration actually lives via live sampling.

**Conflicted (⚠️) — out of scope for this preview**

- The zero-rating / billing-entitlement boundary is conflicted across sources and
  is owned by a downstream solution; `fsi_caibillingentitlement` is scaffolded as
  a shell here and is not resolved in this release.

### ARA boundary — flagged for ratification

CAI **owns a new canonical entity, `fsi_copilotagent`**, and does **not** modify
`agent-registry-automation`'s legacy `fsi_agentinventory` (amendments §2,
decision C4 — option (b)). The intended end state is that `agent-registry-automation`
Flow 1 (Daily Discovery) is refactored to **read** `fsi_copilotagent` after
coverage-parity is validated; `fsi_agentinventory` remains a legacy table during
migration.

> **This boundary is an assumption pending Jude's ratification.** Option (b)
> avoids a breaking change to a live solution at the cost of a temporary
> two-table period. The in-place alternative (extending `fsi_agentinventory`) was
> not chosen because it would couple this foundation to ARA's existing schema and
> ownership.

## Documentation

- [Architecture](docs/architecture.md) — four-layer discovery, 9-entity model, scale engine
- [Prerequisites](docs/prerequisites.md) — auth, roles, scopes, network endpoints
- [Dataverse Schema](docs/dataverse-schema.md) — table, column, and option-set reference
- [Flow Setup](docs/flow-configuration.md) — daily discovery flow build guide
- [Changelog](CHANGELOG.md) — version history

## License

MIT License — See [LICENSE](../LICENSE)
