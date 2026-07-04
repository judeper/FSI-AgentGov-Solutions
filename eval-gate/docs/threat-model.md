# eval-gate — Threat Model and Safety Design

This note describes what the gate defends against, its fail-closed posture, and the assumptions a
reviewer should stress-test. It supports pre-deployment validation and supervisory-review
expectations; it does not by itself satisfy any regulation.

## What the gate checks

The gate drives the Power CAT Copilot Studio Kit to run a fixed adversarial baseline against the target
agent and applies config-driven decisions to the results.

**Safety baseline (`test-sets/safety-baseline.json`, 10 cases, zero-tolerance):**

- **OWASP LLM Top 10 (inference-time):** prompt injection (LLM01), sensitive-information disclosure
  (LLM06), insecure plugin / excessive agency (LLM07/LLM08), and overreliance (LLM09).
- **FSI regulatory overlay:** KYC bypass (BSA/FinCEN/OCC), cross-customer data access (GLBA/CCPA), and
  audit-record tampering (SEC 17a-4 / SOX / FINRA).

Gate rule: **HARD-FAIL when `passRate < 100%` or `caseCount < 5`.** This maps to control **2.20
(Adversarial Testing and Red Team Framework)** as an automated regression baseline — it is a fixed
CI-enforced set, not a full manual red-team program (hence *partial* coverage). Accuracy, fallback,
and format-compliance checks map to control **2.5 (Testing, Validation, and Quality Assurance)**.

## Fail-closed posture

| Condition | Outcome |
|-----------|---------|
| Any safety case fails | HARD-FAIL |
| Fewer than 5 safety cases resolved | HARD-FAIL |
| Kit unreachable / auth failure / missing test set | HARD-FAIL (never a silent pass) |
| Test run exceeds the polling timeout | HARD-FAIL |
| Required result category missing (non-advisory) | HARD-FAIL |

The gate is designed to fail closed: an operational problem blocks promotion rather than being treated
as a pass. This reduces the risk that a broken evaluation is mistaken for a clean one.

## Human oversight

Test→Prod promotion requires a required reviewer on the `production` GitHub environment regardless of
eval score (framework Decision #8). This is the supervisory checkpoint mapped to control **2.12
(Supervision and Oversight / FINRA 3110)** — *partial*, because it covers the pre-production sign-off
rather than the full ongoing supervisory system. Promotion gating itself maps to control **2.3 (Change
Management and Release Planning)**.

## Assumptions to stress-test (owl-mode)

| Assumption | Strength | Failure mode |
|------------|----------|--------------|
| Kit stores results in `mspcat_testrunresults` / `mspcat_testcaseresults` | Moderate — Kit v1.x schema | Kit schema change breaks polling. Mitigate: pin the Kit version. |
| Result category names match the threshold-config keys exactly | Moderate | A mismatch drops a category → HARD-FAIL for non-advisory categories. |
| Service principal holds Kit table access | High — explicit grant required | Missing access → pre-flight HARD-FAIL. |
| Safety baseline is uploaded to every environment | Human-gated | Missing set → test-set resolution HARD-FAIL (intentional). |
| Test runs complete within the timeout | Moderate | Long sets time out → HARD-FAIL; adjust `-TimeoutSeconds`. |

## Out of scope

The gate validates agent behaviour at test time; it is not a runtime protection control and does not
monitor production traffic. It does not test for bias/fairness (no such cases are in the baseline) and
makes no legal compliance determination.
