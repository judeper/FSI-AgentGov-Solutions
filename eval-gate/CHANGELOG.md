# Changelog

All notable changes to this solution are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0-preview] - 2026-07-03

### Added

- Governance registration of the eval-gate CI tooling into the FSI-AgentGov control catalog:
  `manifest.yaml` mapping controls **2.3** (Change Management and Release Planning, full),
  **2.5** (Testing, Validation, and Quality Assurance, full), **2.12** (Supervision and Oversight /
  FINRA 3110, partial — the Test→Prod human sign-off), and **2.20** (Adversarial Testing and Red Team
  Framework, partial — the OWASP LLM Top 10 + FSI safety baseline). eval-gate is the first solution to
  cover control 2.20 (lifecycle-ops, tier 2, preview, enterprise zone).
- `controls-covered.json` (generated) and catalog/site registration via `scripts/build-manifest.py`.
- Documentation: `docs/prerequisites.md`, `docs/deployment.md`, and `docs/threat-model.md`.
- `Invoke-EvalGate.ps1` — the CI wrapper around the Power CAT Copilot Studio Kit that applies
  config-driven PASS/SOFT-FAIL/HARD-FAIL logic (`configs/eval-thresholds.json`) and emits a result
  JSON with exit codes 0/1/2.
- `test-sets/safety-baseline.json` — 10 zero-tolerance safety cases (OWASP LLM Top 10 inference-time
  + FSI regulatory overlay), HARD-FAIL when `passRate < 100%` or `caseCount < 5`.
- Promotion workflows `workflows/eval-gate-dev-to-test.yml` (auto on merge to main) and
  `workflows/eval-gate-test-to-prod.yml` (manual dispatch + required reviewer). Placed under
  `eval-gate/workflows/` for visibility; activated by copying into `.github/workflows/`.

### Notes

- Preview status reflects the human-gated prerequisites (Kit install per environment, service-principal
  certificate, GitHub Actions secrets, safety-baseline upload, and the `production` environment
  required-reviewer protection). The gate is inert until those are completed; infrastructure failures
  (Kit unreachable, auth failure) are always HARD-FAIL, never a silent pass.
- The wrapper does not reimplement Direct Line polling or rubric scoring — those run inside the Kit.
  It polls the Kit's `mspcat_testrunresults` / `mspcat_testcaseresults` tables (Kit v1.x schema).
- Supports pre-deployment validation and supervisory-review recordkeeping expectations under
  OCC 2011-12 / Fed SR 11-7, FINRA 3110, SEC 17a-4, and SOX 302/404; it does not by itself satisfy
  any regulation.
