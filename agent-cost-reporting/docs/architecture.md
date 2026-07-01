# Architecture

Agent Cost Reporting uses a deliberately **decoupled, three-layer** design so that volatile billing
APIs are isolated from the durable dataset and the report renderer.

```
                 ┌──────────────┐
 collectors/ ──▶ │ raw extracts │ ──▶ normalize/ ──▶ cost_facts.jsonl ──▶ render/ ──▶ report.html
 (per surface)   │  raw_*.jsonl │     (+ correlate)   (+ cost_facts.csv)   (Jinja2)   (+ evidence pkg)
                 └──────────────┘
```

1. **Ingestion (`scripts/collectors/`)** — one collector per surface. Each acquires a token via the
   correct auth helper, calls the API, writes a `raw_{surface}_{snapshot}.jsonl` extract, and returns
   a `CollectorResult` recorded in the report manifest. Collectors do not interpret cost — they fetch.
2. **Normalization (`scripts/normalize/`)** — `normalize_cost_facts.py` maps raw rows to the
   `cost_fact` schema with provenance/confidence/attribution metadata;
   `correlate_identity_and_scope.py` adds deterministic joins (subscription → billing policy →
   environment) and flags heuristic/unattributable rows. The output `cost_facts.jsonl` is the durable,
   renderer-independent asset.
3. **Rendering (`scripts/render/`)** — `render_report.py` renders a self-contained HTML evidence
   artifact (no CDN, inline SVG); `package_evidence.py` bundles `report.html` + the dataset +
   `manifest.json` + `sha256.txt` for immutable storage.

## Run order

```text
1. Collect:   run each collect_*.py (and import_manual_credits_csv.py) into a shared --out-dir
2. Normalize: normalize_cost_facts.py --in-dir <raw> --out-dir <work>
3. Correlate: correlate_identity_and_scope.py --cost-facts cost_facts.jsonl --out cost_facts.jsonl
4. Render:    render_report.py --cost-facts cost_facts.jsonl --manifest manifest.json --out report.html
5. Package:   package_evidence.py --package-dir <work> --manifest manifest.json
```

Collectors are independent and can run in any order or in parallel; the normalizer consumes whatever
extracts are present, so a missing/skipped surface degrades the report gracefully rather than failing
the run.

## Auth model per surface

| Surface | Helper | Auth | Managed identity? |
|---------|--------|------|-------------------|
| Azure Cost Management | `auth_arm.py` | ARM token, Cost Management Reader | Yes (preferred) |
| Microsoft Graph (usage/license/audit) | `auth_graph.py` | App-only, Reports/Organization/AuditLogsQuery | Yes (preferred) |
| Power Platform API | `auth_powerplatform.py` | Service principal + Power Platform RBAC, client-credentials | **No** (delegated-only API) |
| Manual CSV | — | Admin portal export | n/a |

The Power Platform API exception is documented inline in `auth_powerplatform.py` and is the only
non-managed-identity path in the solution.

See [api-surface-matrix.md](api-surface-matrix.md) for endpoints, API versions, and source dates, and
[known-gaps.md](known-gaps.md) for the items still requiring live-tenant verification.
