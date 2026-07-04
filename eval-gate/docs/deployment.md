# eval-gate — Deployment

The eval-gate ships as CI tooling under `eval-gate/`. Nothing runs until you activate the workflows
and complete the [prerequisites](prerequisites.md).

## Activation steps

1. **Complete the prerequisites** in [prerequisites.md](prerequisites.md) (Kit install, service
   principal, secrets, safety-baseline upload, `production` environment protection).
2. **Copy the workflow files** from `eval-gate/workflows/` into `.github/workflows/`:
   - `eval-gate-dev-to-test.yml` — triggers on merge to `main` (Dev→Test gate; SOFT-FAIL warns).
   - `eval-gate-test-to-prod.yml` — manual dispatch + required reviewer (Test→Prod gate; SOFT-FAIL blocks).
   They live under `eval-gate/workflows/` for visibility so they do not run before you intend them to.
3. **Confirm the test-set ID** matches between the Kit library and the workflow input
   (`safety-baseline-v1` by default).
4. **Run a pre-flight** (`-WhatIf`) against Dev, then a live `DevToTest` run:

   ```powershell
   .\eval-gate\Invoke-EvalGate.ps1 -Environment dev -TestSetId safety-baseline-v1 -PromotionContext DevToTest
   ```

## Gate behaviour

| Context | HARD-FAIL | SOFT-FAIL |
|---------|-----------|-----------|
| Dev → Test | Blocks | Warns, continues |
| Test → Prod | Blocks | Blocks |

Test→Prod additionally requires human sign-off via the `production` GitHub environment, regardless of
eval score. Exit codes: `0` PASS, `1` SOFT-FAIL, `2` HARD-FAIL. Infrastructure failures (Kit
unreachable, auth failure, missing test set) are always HARD-FAIL — the gate fails closed rather than
passing silently.

## Thresholds

Thresholds are config-driven in `configs/eval-thresholds.json`. Safety and fallback are zero-tolerance
(HARD-FAIL below 100%); accuracy and format compliance have SOFT-FAIL bands; latency and topic routing
are advisory (reported, not gated). See the [README](../README.md#gate-thresholds) for the full table.

## Change control

Each gate run produces a result JSON suitable for attachment to the change record for the promotion.
Retain these per your change-control recordkeeping schedule (see `manifest.yaml` `retention`).
