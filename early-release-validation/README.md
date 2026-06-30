---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Early-Release Validation

> **Version:** v0.1.0-preview
> **Status:** Preview
> **Validated against framework version:** v1.6.0
> **Upstream Microsoft dependency:** Preview — The three structural checks run today on GA tooling (PAC CLI + solution YAML). Check 4 (EarlyReleaseReadinessCheck) live probe and the early-release-ring environment-config are deferred pending MSCAT "Building Enterprise AI Solutions" Part 2.

Pre-promotion **resilience validation** for Copilot Studio agents. Before an agent is promoted into
an early-release (preview) ring, this solution checks *how the agent behaves when things break* — it
answers a coverage question (does every failure path have a graceful fallback?), not a quality
question. Results are packaged as tamper-evident Dataverse evidence for change-control review under
OCC 2011-12 / Fed SR 11-7 (pre-deployment validation), SEC 17a-4 (recordkeeping), and FINRA 4511
(books and records). It supports those obligations; it does not by itself satisfy any regulation.

## What this solution does (and does not do)

This is a **pre-flight structural gate**, not a runtime fault-injection test. Copilot Studio exposes
no native connector-failure simulation, so the checks detect *missing* error branches and fallback
coverage rather than proving an error branch fires correctly at runtime. The checks read the
unpacked source of an agent solution (the output of `pac solution unpack`) offline.

| Capability | This solution | What you still need |
|------------|---------------|----------------------|
| Detect topics that call a connector/flow with no error handling | Yes | Author the missing error branches in Copilot Studio |
| Detect hard-coded connection ids that will not rebind per environment | Yes | Convert to per-environment connection references |
| Confirm a System Fallback topic exists with a real message | Yes | Author a non-stub fallback/escalate message |
| Prove a fallback actually fires at runtime under connector failure | No (platform limitation) | Manual/integration testing in the early-release ring |
| Promote / roll back the agent | No | Power Platform pipelines / PPAC |

## Sibling solution

This solution is the resilience counterpart to **eval-gate** (planned), which tests *what an agent
says* (quality scoring via the Copilot Studio evaluation framework). Early-Release Validation tests
*how an agent survives failure* (resilience coverage). They are complementary, not overlapping.

## The four checks

| # | Check | Mechanism | Pass / Fail |
|---|-------|-----------|-------------|
| 1 | **FallbackCoverageCheck** | Inspects each topic YAML for a connector/flow action with no accompanying error-handling construct | Fail if any topic calls a connector/flow with no error branch |
| 2 | **ConnectorResilienceCheck** | Inspects connection-reference definitions for hard-coded `connectionid` values | Fail if a hard-coded connection id is found |
| 3 | **ErrorRecoveryCheck** | Confirms a System Fallback topic (and Escalate topic when present) has a non-stub user-facing message | Fail if the fallback is missing or empty/stub |
| 4 | **EarlyReleaseReadinessCheck** | Composite: runs checks 1–3, then a live probe against the deployed agent | **Deferred** — the live probe is blocked on MSCAT Part 2 (see below); reports `Skipped` and `PromotionReady = false` |

The detection markers for checks 1–3 are intentionally editable constants at the top of
`scripts/Invoke-EarlyReleaseValidation.ps1` because `pac solution unpack` node names vary by
platform version. See [docs/fallback-testing-guide.md](docs/fallback-testing-guide.md) to tune them.

## Usage

```powershell
# Export and unpack the agent solution first (Power Platform CLI)
pac solution export --name MyAgentSolution --path ./MyAgentSolution.zip
pac solution unpack --zipfile ./MyAgentSolution.zip --folder ./unpacked

# Run the three structural checks (offline; no credentials required)
./scripts/Invoke-EarlyReleaseValidation.ps1 -CheckType AllStructural -SolutionPath ./unpacked

# Run the composite readiness gate and persist evidence to Dataverse
./scripts/Invoke-EarlyReleaseValidation.ps1 -CheckType EarlyReleaseReadinessCheck `
    -SolutionPath ./unpacked `
    -AgentId "00000000-0000-0000-0000-000000000000" `
    -AgentVersion "1.4.0" `
    -Environment "https://your-org.crm.dynamics.com" `
    -AccessToken $token

# Package evidence for supervisory review (JSON + SHA-256 companion)
./scripts/Export-ValidationEvidence.ps1 -Environment "https://your-org.crm.dynamics.com" -OutputDir ./evidence
```

**Exit codes** (`Invoke-EarlyReleaseValidation.ps1`): `0` = pass, `1` = resilience gap
detected, `2` = checks ran but Dataverse evidence write failed, `3` = early-release readiness
deferred / not promotion-ready (live probe pending MSCAT Part 2 — do not auto-promote on `0`).

## Architecture

```
pac solution unpack ──▶ unpacked/ ──▶ Invoke-EarlyReleaseValidation.ps1 ──▶ fsi_ervalidationresult
   (offline source)      (topic YAML +     (checks 1–3 offline;              (Dataverse evidence)
                          connection refs)   check 4 deferred)                        │
                                                                                      ▼
                                                          Export-ValidationEvidence.ps1 ──▶ evidence JSON + .sha256
```

## Dataverse schema

The `fsi_ervalidationresult` table records one row per check (test type, status, gap count,
promotion-ready flag, finding-detail JSON, and a SHA-256 evidence hash). Full column reference:
[docs/dataverse-schema.md](docs/dataverse-schema.md) (generated from
`scripts/create_erv_dataverse_schema.py` — regenerate with `--output-docs`).

```bash
python scripts/create_erv_dataverse_schema.py --output-docs
```

## Implemented controls

| Control | Why |
|---------|-----|
| 2.1 | Environment lifecycle — validates readiness for early-release-ring promotion |
| 2.4 | Operational resilience / continuity — validates fallback and recovery behavior |
| 2.8 | Release management / change control — gates early-release promotion with evidence |
| 1.9 | Validation testing before environment promotion |

## Blocking dependency: MSCAT Part 2

The MSCAT "Building Enterprise AI Solutions" Part 1 (ALM foundations) post references a follow-on
covering early-release validation, hotfix environments, and source control. Until that **Part 2**
publishes the early-release-ring environment-config schema, two pieces stay deferred:

- `scripts/create_erv_environment_variables.py` — a documented stub that exits non-zero so it cannot
  be mistaken for a successful step.
- **Check 4 (EarlyReleaseReadinessCheck)** live probe — the composite gate runs the three structural
  checks and records `PromotionReady = false` with a `Skipped` live-probe finding.

The three structural checks have no dependency on MSCAT Part 2 and are usable today.

## Prerequisites

See [docs/prerequisites.md](docs/prerequisites.md). In short: Power Platform CLI for export/unpack,
a Microsoft Entra app registration (or managed identity) for optional Dataverse evidence writes, and
Dataverse system administrator access to create the schema.

## Documentation

- [docs/prerequisites.md](docs/prerequisites.md)
- [docs/fallback-testing-guide.md](docs/fallback-testing-guide.md)
- [docs/troubleshooting.md](docs/troubleshooting.md)
- [docs/dataverse-schema.md](docs/dataverse-schema.md) (generated)
