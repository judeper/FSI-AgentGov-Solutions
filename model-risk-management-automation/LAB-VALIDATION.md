# Lab Validation Report — Model Risk Management Automation

> **Solution:** `model-risk-management-automation` · **Version:** v1.0.4
> **Validation date:** 2026-06-04 · **Mode:** Static (no live tenant) — parse-validity, authoritative-source verification, doc completeness
> **Verdict:** **Lab-ready** with documented runtime-only caveats.

## Purpose & Controls

Automated OCC / Fed model risk management (MRM) workflows for AI agents on Power
Platform: model inventory submission, risk scoring, independent validation
workflows, ongoing monitoring, and examiner-facing Agent Card generation.

- **Primary control:** 2.6 — Model Risk Management
- **Secondary controls:** 2.5, 2.9, 2.11, 2.13, 3.1, 1.2

## What Was Checked

| Area | Method | Result |
|------|--------|--------|
| Python scripts (5) | `python -m py_compile` | Pass — all compile |
| PowerShell scripts (2) | `Parser::ParseFile` (zero errors) | Pass after fixes |
| Dataverse column / option-set references | Cross-checked every `$select`/`$filter` against `create_mrm_dataverse_schema.py` and `docs/dataverse-schema.md` | Consistent |
| Option-set value drift (0/1/2 vs 100000000+) | Reviewed all picklist references in scripts and docs | No drift — all use 100000000-base integers |
| Regulatory citations (OCC / Fed SR) | Authoritative web verification | Accurate (see below) |
| Language rules (prohibited absolute-compliance phrasing) | grep across all `*.md` | Zero violations |
| Agent Card generation | Reviewed template + Flow 5 build steps | Internal MRM evidence JSON (not external A2A/manifest schema) — appropriate |
| Auth model / token audiences | Reviewed both PowerShell scripts + Python shared client | Managed-identity-first; SecureString bug fixed |
| Graph / Power Platform / Agent 365 API references | Cross-checked against docs; preview APIs feature-flagged | Appropriately hedged |

## Authoritative Sources Cited

- **Federal Reserve SR 26-2** (the agency's own supervisory letter): confirms
  Revised Interagency Guidance on Model Risk Management, issued April 17, 2026,
  supersedes/rescinds SR 11-7, and that generative/agentic AI is excluded from
  scope — https://www.federalreserve.gov/supervisionreg/srletters/SR2602.htm
- **OCC Bulletin 2026-13 / FDIC** corroboration (legal advisories):
  https://www.sullcrom.com/insights/memo/2026/April/OCC-Fed-FDIC-Issue-Revised-Guidance-Model-Risk-Management ,
  https://www.davispolk.com/insights/client-update/visual-memo-key-changes-under-federal-banking-agencies-revised-model-risk
- **`Get-AzAccessToken` returns `SecureString` from Az.Accounts 5.0.0+** —
  https://learn.microsoft.com/powershell/azure/protect-secrets and
  https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken
  (syntax shows `-AsSecureString`). Cross-confirmed by the Microsoft Graph
  PowerShell IDX14102 troubleshooting article, which states the SecureString
  change began at Az.Accounts 5.0.0.

The README/manifest's regulatory framing — "OCC Bulletin 2026-13 (formerly OCC
2011-12) / Fed SR 26-2 (formerly Fed SR 11-7)" with the GenAI/agentic-AI scope
exclusion note — matches the authoritative sources. No regulatory-citation
changes were required.

## Gaps Found & Fixes Applied

### Fixed (scripts)

1. **`Deploy-MRM-Baseline.ps1` — broken OData query (functional bug).**
   Lines building `$agentQuery` used `"?$filter=..."` and `"&$select=..."`
   inside double-quoted strings, so PowerShell interpolated `$filter`/`$select`
   as undefined variables (empty), producing a malformed URL
   (`...?=...&=...`). Backtick-escaped to `` `$filter `` / `` `$select `` so the
   query renders as `?$filter=...&$select=...`. (The sibling query at the
   `fsi_modelinventories` step was already correctly escaped.)

2. **`Deploy-MRM-Baseline.ps1` & `Test-MRMCompliance.ps1` — SecureString token
   handling (auth break on current Az modules).** Both used
   `(Get-AzAccessToken -ResourceUrl ...).Token` directly in `"Bearer $dvToken"`.
   On **Az.Accounts 5.0.0+** (current GA), `.Token` is a `SecureString`, which
   stringifies to `System.Security.SecureString` and breaks the Authorization
   header. Changed to request `-AsSecureString` explicitly and convert via
   `[System.Net.NetworkCredential]::new('', $secureToken).Password`. This is
   forward/backward compatible across module versions and follows the
   Microsoft-documented conversion guidance.

### Verified clean (no change needed)

- `Test-MRMCompliance.ps1` option-set defaults (`Validated=100000006`,
  `Severity Critical=100000001`, `Remediation Closed=100000004`,
  `Tier1=100000001`) all match the schema.
- Entity-set pluralizations (`fsi_modelinventories`, `fsi_validationcycles`,
  `fsi_validationfindings`, `fsi_monitoringrecords`, `fsi_mrmcomplianceevents`)
  are correct.
- `docs/troubleshooting.md` and `docs/flow-configuration.md` OData queries use
  correct lookup columns (`_fsi_modelinventory_lookup_value`) and integer
  option-set values — prior council fixes intact.
- No prohibited absolute-compliance language anywhere in the solution docs.

## Runtime-Only Caveats (cannot be statically verified)

- **No live tenant** — token acquisition, Dataverse reads/writes, flow execution,
  SharePoint Agent Card upload, and Word Online generation were not executed.
- **OptionSet integers are deployment-dependent.** Dataverse may assign
  different integers if option sets are created in a different order. Both
  PowerShell scripts and the flow docs already warn operators to confirm values
  against the deployed solution XML and record them in `DELIVERY-CHECKLIST.md`.
- **Agent 365 / Microsoft Entra Agent ID enrichment is preview.** Permission
  names (`CopilotPackages.Read.All`, `AgentInstance.Read.All`) and the beta paths
  (`/beta/copilot/admin/catalog/packages`, `/agentRegistry/agentInstances`) are
  emerging surfaces. The solution gates them behind `IsAgent365LifecycleEnabled`
  (default `false`) and documents "use the API path your tenant has approved" —
  operators must verify against current Microsoft Learn at deployment time.
- **`PowerPlatform.Admin.Read.All`** is documented as illustrative; confirm the
  exact Power Platform API scope your tenant exposes during managed-identity setup.

## Final Assessment

**Lab-ready.** Two genuine defects in the operational PowerShell scripts (a
malformed OData query and SecureString token handling that would break on the
current Az.Accounts GA) were repaired and verified. All Dataverse column and
option-set references are consistent with the schema source of truth, regulatory
citations are accurate against authoritative agency sources, and there are no
language-rule violations. Remaining items are runtime/preview verifications that
require a live tenant and are already flagged for operators in the delivery
checklist and prerequisites.
