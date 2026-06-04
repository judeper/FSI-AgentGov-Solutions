# Lab Validation Report — FINRA Supervision Workflow

> **Solution version:** v1.1.1
> **Validation date:** 2026-06-04
> **Validation type:** Static (parse-validity + authoritative-source verification + doc completeness). No live tenant was used.
> **Verdict:** **Lab-ready** (with documented runtime-only caveats below).

## 1. Purpose and Controls

Automated **retrospective** supervision workflow for AI agent outputs to support **FINRA Rule 3110** compliance. Provides a post-delivery review queue, SLA tracking, escalation, append-only Dataverse audit logging, and WORM-ready evidence export fed by Microsoft Purview Communication Compliance.

| Control | Coverage | Notes |
|---------|----------|-------|
| 2.12 — Supervision and Oversight (FINRA Rule 3110) | full | Retrospective arm only; pre-delivery HITL is delegated to `hitl-workflow-governance` (correctly scoped in README). |
| 1.10 — Communication Compliance | full | Purview Communication Compliance as the upstream alert source. |
| 1.7 — Audit Logging | full | Append-only `fsi_supervisionlog` + Dataverse auditing. |

`controls-covered.json` and `manifest.yaml` agree (2.12, 1.10, 1.7). `manifest.yaml` was **not** modified.

## 2. What Was Checked

| Area | Method | Result |
|------|--------|--------|
| Python parse-validity | `python -m py_compile` on `auth.py`, `deploy.py`, `export_supervision_evidence.py`, `test_export_supervision_evidence.py` | PASS (exit 0) |
| Unit tests | `python -m pytest scripts/test_export_supervision_evidence.py -q` | PASS (15 passed) |
| Dataverse column naming | grep for snake_case `fsi_*_*` across solution | No violations (all logical names, e.g. `fsi_agentid`, `fsi_reviewoutcome`) |
| Option-set value drift | Cross-checked `deploy.py`, `export_supervision_evidence.py` constants, README, `docs/dataverse-schema.md`, Power BI DAX, flow docs | Internally consistent small-integer scheme (1..n); README Step 1.5 instructs operators to set these explicitly rather than accept 100000000+ defaults |
| FSI language rules | grep `ensures\|guarantees\|will prevent\|eliminates risk` in `*.md` | No violations |
| Auth model | Reviewed `auth.py` | Managed-identity-first; client secret marked `# legacy: dev-only`; Dataverse token audience `<env>/.default` is correct |
| Schema ↔ script ↔ doc consistency | Column references in scripts/DAX/flows vs `docs/dataverse-schema.md` | Consistent |

## 3. Authoritative Source Verification

Every load-bearing platform/API claim was checked against Microsoft Learn (and FINRA for regulatory citations).

| Claim (where used) | Verified outcome | Source |
|--------------------|------------------|--------|
| Power Automate / Logic Apps `rand(min, max)` upper bound is **exclusive** → `rand(1, 101)` yields 1..100 (flow-configuration.md sampling; `.ralph-config.json` fact) | **Confirmed**: "returns a random integer from the specified range, excluding the maximum value" | [WDL functions reference](https://learn.microsoft.com/azure/logic-apps/workflow-definition-language-functions-reference) |
| DAX `WEEKDAY(date, 2)` gives **Monday=1..Sunday=7** week boundaries (power-bi-setup.md "Items This Week" / "WoW Change"; `.ralph-config.json` fact) | **Confirmed**: return_type 2 = "week begins on Monday (1) and ends on Sunday (7)" | [WEEKDAY (DAX)](https://learn.microsoft.com/dax/weekday-function-dax) |
| `Get-SupervisoryReviewPolicyV2` / `Get-SupervisoryReviewPolicy` available via `Connect-IPPSSession` (README & flow-configuration.md API fallback note; communication-compliance-setup.md Step 5) | **Confirmed**: functional in Security & Compliance PowerShell | [Get-SupervisoryReviewPolicyV2](https://learn.microsoft.com/powershell/module/exchangepowershell/get-supervisoryreviewpolicyv2) |
| `security/alerts_v2` Graph API serves **Defender** alerts, not Communication Compliance (communication-compliance-setup.md Step 5 note) | **Confirmed**: alerts_v2 is the Microsoft Defender/XDR alerts surface | [List alerts_v2](https://learn.microsoft.com/graph/api/security-list-alerts_v2) |
| Power BI refresh cadence limits — Pro/shared = 8/day; Premium/PPU = 48/day (basis for the doc fix in §4) | **Confirmed**: "up to eight daily time slots ... on shared capacity, or 48 time slots on Power BI Premium" | [Data refresh in Power BI](https://learn.microsoft.com/power-bi/connect-data/refresh-data#data-refresh) |
| Managed-identity auth chain (`ManagedIdentityCredential`, `DefaultAzureCredential`) in `auth.py` | **Confirmed** as the recommended credential types | [azure-identity DefaultAzureCredential](https://learn.microsoft.com/python/api/azure-identity/azure.identity.defaultazurecredential) |
| Approvals connector outputs, parallel approvals, Teams Universal Actions / Adaptive Card `refresh.userIds` + `Action.Execute`, Outlook Actionable Messages (flow-configuration.md optional approval surface) | Citations present and resolve to current Microsoft Learn pages | Links embedded in `docs/flow-configuration.md` |
| Azure Blob immutable (WORM) storage, Purview records management, Graph eDiscovery holds (README evidence guidance) | Citations present and resolve | Links embedded in README |
| FINRA Regulatory Notice 24-09 (Gen AI supervision guidance) | Title/number correct | <https://www.finra.org/rules-guidance/notices/24-09> |
| SEC 17a-4(b)(4) 3-year communications retention vs FINRA 4511(b) 6-year retention | Citations correctly distinguished in README (corrected in prior v1.0.1) | FINRA Rule 4511; SEA Rule 17a-4 |

The undocumented `compliance.microsoft.com/api/SupervisoryReview/alerts` ingestion endpoint is **explicitly flagged** as unsupported in both the README and flow docs, with the supported `Connect-IPPSSession` PowerShell fallback documented. This is the correct posture for a lab deployment.

## 4. Gaps Identified and Fixes Applied

| # | Gap | Severity | Fix |
|---|-----|----------|-----|
| 1 | `docs/power-bi-setup.md` Step 5 prescribed "Scheduled refresh: Every 30 minutes" and a contradictory "Frequency: Daily" table while listing **Power BI Pro** as an option. A 30-minute cadence (48 refreshes/day) is not achievable on Pro/shared capacity (8/day cap). | Minor (doc accuracy; misleading for Pro-licensed labs) | Replaced with capacity-based guidance: Pro/shared = up to 8/day; Premium/PPU = up to 48/day. Added authoritative Microsoft Learn citation. |

No other corrections were required. Scripts, schema docs, security-role matrix, flow specifications, prerequisites, and troubleshooting content were already accurate and internally consistent (the solution carries an extensive council-review history through v1.1.1).

### Minor observations (not changed — no action needed for lab)

- `deploy.py` / `export_supervision_evidence.py` Dataverse host-pattern check is **warning-only** and accepts commercial + US/DE sovereign suffixes. GCC High / DoD operators using other suffixes (e.g., `*.crm.appsplatform.us`) will see a non-fatal warning only; behavior is correct.
- `templates/SupervisionDashboard.pbit` and `generate_3120_report.py` / `verify_role_privileges.py` are documented as **planned, not yet implemented**; the docs correctly route operators to the manual alternatives. These are intentional roadmap items, not gaps.

## 5. Runtime-Only Caveats (cannot be validated without a live tenant)

The following require a provisioned Dataverse environment + M365 E5 Compliance + Power Automate and are out of scope for static validation:

1. **Communication Compliance alert ingestion** end-to-end (the undocumented endpoint vs the `Connect-IPPSSession` fallback) — verify in lab before relying on automated ingestion.
2. **Table/column creation**: `deploy.py` creates table shells only; choice columns and option-set integer values must be created manually per `docs/dataverse-schema.md` Step 1.5. Verify the small-integer option-set values are applied (not the 100000000+ defaults) or every downstream filter/DAX measure will be wrong.
3. **Security role provisioning** is manual; verify the privilege matrix in `docs/security-roles.md` (notably: no Delete on `fsi_supervisionqueue`; no Write/Delete on `fsi_supervisionlog`).
4. **Flow behavior** (sampling, assignment, SLA/escalation timing, the Pending→InReview transition, and the EscalationFlow/ReviewComplete double-trigger guard) must be validated with test alerts.
5. **Evidence export integrity**: confirm SHA-256 manifest + `.sha256` sidecar, then confirm WORM/retention placement (Azure Blob immutability or Purview records management) — Dataverse append-only design is not, by itself, WORM.
6. **Power BI refresh cadence** against the actual purchased capacity (see §4 fix).

## 6. Lab-Readiness Assessment

**Lab-ready.** All scripts parse and pass their unit tests; all authoritative claims tested resolve to current Microsoft sources; no language-rule or column-naming violations; option-set values are internally consistent with explicit operator guidance. One minor documentation inaccuracy (Power BI refresh cadence) was corrected. Remaining unknowns are inherently runtime-only and are clearly documented for the lab operator. A deployer following the README + docs can stand up the solution in a lab and validate the runtime caveats in §5.
