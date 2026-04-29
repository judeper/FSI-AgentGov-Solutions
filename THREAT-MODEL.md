# Threat Model — FSI-AgentGov-Solutions

This document captures the high-level threat model for `FSI-AgentGov-Solutions`. It is deliberately concise: this repo ships scripts, schemas, manifests, and one Dataverse plugin source file. It does not host a production service.

The model uses a lightweight STRIDE-by-asset framing.

## Assets

| Asset | Description | Where it lives |
|-------|-------------|----------------|
| Governance scripts | PowerShell / Python / KQL that read tenant state and write Dataverse records. | `*/scripts/**` |
| Dataverse schema generators | Python clients that create/alter Dataverse tables, columns, and option sets via the Web API. | `*/scripts/create_*_dataverse_schema.py`, `scripts/shared/dataverse_client.py` |
| Dataverse plugin (MIME validation) | C# plugin that runs server-side inside the Dataverse sandbox. | `mime-type-restrictions/src/ValidateMimeTypePlugin.cs` |
| Reference documentation | Manual flow-build instructions, security configuration guidance. | `*/docs/**`, `DEPLOYMENT-GUIDE.md` |
| Manifests + lock file | Single source of truth for the catalog (`*/manifest.yaml`, `solutions.json`). | Repo root + per-solution |
| CI workflows | Build/check/health workflows that run with `GITHUB_TOKEN` permissions. | `.github/workflows/**` |

## Trust boundaries

```
                ┌──────────────────────────────────────────┐
                │  Customer tenant (M365 / Power Platform) │
                │   - Entra ID                             │
                │   - Power Platform environments          │
                │   - Dataverse                            │
                └────────────────────────────┬─────────────┘
                                             │ MSAL token / managed identity
                                             ▼
┌────────────────────┐   git pull / clone   ┌───────────────────────────┐
│  FSI-AgentGov-     │ ───────────────────▶ │  Customer admin workstation│
│  Solutions repo    │                      │  or CI runner              │
│  (public, MIT)     │                      │  - runs governance scripts │
└────────┬───────────┘                      │  - runs schema generators  │
         │                                  │  - builds plugin (rare)    │
         │ contributors                     └────────────┬──────────────┘
         ▼                                               │
┌──────────────────────┐                                 │ Dataverse Web API
│  GitHub Actions CI   │                                 ▼
│  (build, test,       │                       ┌──────────────────────┐
│   secret scanning)   │                       │  Production Dataverse│
└──────────────────────┘                       │  + Copilot Studio    │
                                               └──────────────────────┘
```

## Threats and mitigations

### Repository content (S/T/I)

| Threat | Mitigation |
|--------|------------|
| Secret committed to repo (token, client secret, certificate) | `gitleaks` workflow on every push/PR; `SECURITY.md` private reporting; reviewer checklist. |
| Compliance language drift creating legal exposure | `language-rules.yml` workflow bans "ensures compliance" / "guarantees compliance". |
| Manifest referencing unknown framework controls | `manifest-check.yml` validates against pinned framework `controls.json`. |
| Stale framework reference creating control drift | Both manifest-check and publish-docs workflows pin the framework to `${{ vars.FRAMEWORK_REF \|\| 'v1.4.0' }}`. |
| Dataverse logical-name typos in OData queries causing silent failures or unfiltered reads | `odata-lint.yml` (soft-gate) plus AGENTS.md / CLAUDE.md naming rule; promote to `--strict` once the 5 known bugs are fixed. |

### Customer-side execution (E/I/D)

| Threat | Mitigation |
|--------|------------|
| Adopter runs scripts with overly broad credentials (long-lived client secret with Global Admin) | Document **managed-identity-first** standard in `AGENTS.md`; flag client-secret paths as legacy/dev-only; SECURITY.md reporting channel for any script that escalates beyond declared scope. |
| Schema generators alter the wrong environment (prod vs dev mix-up) | All Dataverse schema scripts support `--dry-run`; `dataverse_client.py` requires explicit environment URL; README quickstart shows `--dry-run` first. |
| Governance script exfiltrates tenant data via documentation/log output | Scripts log via `logging` module (Python) or write-host (PowerShell); customer should run inside their boundary. No data is sent off-tenant by any script in this repo. |
| Plugin tampered with at build time | Plugin source is small (single file); customers SHOULD review and sign their own build. We do **not** publish a signed binary today (tracked as P2 work). |

### CI / supply chain (T/E)

| Threat | Mitigation |
|--------|------------|
| Compromised third-party action injects code into release pipeline | `dependency-review.yml` on PRs; pin action versions to commit SHAs in future hardening pass. |
| Dependency confusion / typosquat in `requirements*.txt` | `dependency-review.yml`; CodeQL Python workflow; review changes to `requirements*.txt` carefully. |
| Workflow secret leak via `pull_request_target` mis-use | None of our workflows use `pull_request_target`; `gitleaks` and `dependency-review` use `pull_request` only. |

### Plugin trust boundary (T/I)

The MIME validation plugin runs **inside the Dataverse sandbox** under the calling user's context. Threats specific to this surface:

| Threat | Mitigation |
|--------|------------|
| Plugin accepts attacker-supplied MIME header without verifying actual file contents | Plugin must perform server-side MIME sniffing on the file body, not trust client-declared MIME. (See `mime-type-restrictions/docs/`.) |
| Plugin fails open (allows upload) on exception | Plugin throws `InvalidPluginExecutionException` to halt the operation, not catch-and-continue. |
| Plugin assemblies redistributed without signature verification | Customers should rebuild from source and sign with their own key. We do not publish a binary today. |

## Out of scope

- Threats originating inside Microsoft cloud services (Power Platform, Dataverse, Entra ID). Report those to MSRC.
- Customer-built Power Automate flows constructed from our manual instructions.
- Customer customisations of the schema generators or governance scripts.

## Open items (tracked elsewhere)

- Promote `lint-odata-columns.py` from soft-gate to `--strict` after fixing the 5 known logical-name bugs.
- Publish signed plugin binary + provide a `dotnet build` workflow once a `.csproj` is added.
- Switch CI action references from version tags to commit SHAs.
- Add SBOM generation and signed release artifacts (P2 in the critique-remediation plan).
