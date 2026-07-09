---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P2, P4]
applicable_drivers:
  - ai_governance
coe_function: govern
---
# Copilot Agent Inventory

> **Version:** v0.2.0-preview
> **Status:** Preview
> **Validated against framework version:** v1.6.0
> **Upstream Microsoft dependency:** Mixed — ARG Power Platform Inventory GA Mar 31 2026; several agent-specific fields (isManaged, channels, authentication, capabilitiesCounts, powerPlatformConnectors) are still preview.
> **Last Verified:** 2026-06-12

Tenant-wide discovery and a canonical Dataverse **system-of-record** for every
Copilot Studio and Microsoft 365 Copilot Agent Builder agent. Copilot Agent
Inventory (CAI) is the tier-1 foundation that downstream FSI governance solutions
read from, rather than each re-scanning the platform. This solution targets the
**US commercial Microsoft 365 / Power Platform cloud**.

## Overview

CAI composes a three-layer discovery (Azure Resource Graph → per-environment
Dataverse → PPAC reconciliation) and normalizes the result into eight Dataverse
tables. A complete, current agent inventory is required for agent registry
control 1.2 and supports compliance with the record-keeping expectations of
FINRA Rule 4511 and SEC Rule 17a-3/17a-4 (a documented inventory is a
prerequisite for the records those rules require). The inventory also provides
the agent dimension that management and reporting solutions join against.

Unlike `agent-registry-automation` (which operates a registration and approval
workflow over its legacy `fsi_agentinventory` table), CAI owns the **canonical
discovery store** `fsi_copilotagent` and is built for tenant scale (~2,000
agents) with delta change tracking and batched writes. See
[ARA boundary](#ara-boundary-flagged-for-ratification) below.

## Architecture

Full detail in [docs/architecture.md](docs/architecture.md). In summary:

**Three-layer discovery**

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

**8-entity model** (logical names): `fsi_copilotagent` (master),
`fsi_caienvironment`, `fsi_caiagentfeature` (one row per detected feature),
`fsi_caiauthshare`, `fsi_caibillingentitlement` (downstream shell),
`fsi_caiusagesignal`, `fsi_caiworkiqstate` (downstream shell),
`fsi_caicompliancestate`.

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
│   ├── create_cai_dataverse_schema.py   # 8-entity schema, idempotent, --output-docs
│   ├── discover_agents.py               # three-layer discovery scanner
│   ├── detect_people_capability.py      # declarative-agent People capability (manifest)
│   ├── expand_audience_upns.py          # sharing audience -> member UPNs (Graph transitive)
│   └── requirements.txt
└── templates/
    ├── agent-record.sample.json         # sample fsi_copilotagent + feature rows
    ├── people-detection.sample.json     # sample People-capability detection artifact
    ├── audience-input.sample.json       # sample sharing posture (expand input)
    └── audience-upn-list.sample.json    # sample CBG-shaped intendedUsers artifact
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

# 3. Run the discovery scanner (dry-run first)
python scripts/discover_agents.py \
    --environment-url https://governance.crm.dynamics.com \
    --tenant-id <your-tenant-id> --dry-run --output scan.json

# 4. Production run (managed identity preferred)
python scripts/discover_agents.py \
    --environment-url https://governance.crm.dynamics.com \
    --tenant-id <your-tenant-id> --auth-mode managed-identity

# 5. Detect the declarative-agent "People" capability from manifests
#    (source-repo tree or local app-package directory/zip; --dry-run plans only)
python scripts/detect_people_capability.py \
    --source source-repo --path ../my-agent-repo \
    --id-map ./agent-id-map.json --output people.json

# 6. Expand each agent's sharing audience to member UPNs (CBG input)
#    --dry-run resolves nothing over the network
python scripts/expand_audience_upns.py \
    --input authshare.json --auth-mode managed-identity \
    --output intended-users.json
```

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

- [Architecture](docs/architecture.md) — three-layer discovery, 8-entity model, scale engine
- [Prerequisites](docs/prerequisites.md) — auth, roles, scopes, network endpoints
- [Dataverse Schema](docs/dataverse-schema.md) — table, column, and option-set reference
- [Flow Setup](docs/flow-configuration.md) — daily discovery flow build guide
- [Changelog](CHANGELOG.md) — version history

## License

MIT License — See [LICENSE](../LICENSE)
