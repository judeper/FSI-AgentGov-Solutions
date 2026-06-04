# Lab Validation Report — Scope Drift Monitor

> **Version validated:** v1.2.2
> **Validation type:** Static (no live tenant) — parse-validity + authoritative-source verification + doc completeness
> **Date:** 2026-06-04

## Purpose and Controls

The Scope Drift Monitor detects AI agent data access beyond declared operational scope.
It compares each agent's **declared scope** (allowed connectors, SharePoint sites,
Dataverse tables, external APIs — stored as JSON arrays on the `fsi_agentscope` Dataverse
table) against **actual access** observed in Copilot interaction audit events, and records
out-of-scope access as `fsi_scopeviolation` rows.

Primary framework controls: **1.14** (Data Minimization and Agent Scope Control),
**1.4** (Advanced Connector Policies), **1.5** (DLP and Sensitivity Labels). Supports
GDPR Art. 5(1)(c), GLBA Section 501(b), and CCPA purpose limitation.

## What Was Checked

- Conventions: root `AGENTS.md`, `.github/copilot-instructions.md`, FSI language rules,
  Dataverse column-naming rules, `.ralph-config.json` domain facts.
- All three PowerShell scripts (`Invoke-DriftScan.ps1`, `New-AgentBaseline.ps1`,
  `Test-AlertDelivery.ps1`) — parse validity, auth model, API call shapes, Dataverse
  column references, option-set values.
- All five docs (`prerequisites.md`, `dataverse-schema.md`, `baseline-configuration.md`,
  `flow-configuration.md`, `troubleshooting.md`), `README.md`, `CHANGELOG.md`, `manifest.yaml`.
- Declared-vs-actual scope mechanics: Copilot audit `RecordType`/`CopilotEventData` schema,
  Office 365 Management API content/subscription shape, required permissions, token
  audiences, and current product/feature naming.

## Authoritative Sources Cited

1. Copilot interaction events overview / Audit Copilot schema (RecordType 261 =
   `CopilotInteraction`; `CopilotEventData` fields `AISystemPlugin`, `AccessedResources`,
   `Contexts`, `AppHost`, `ThreadID`, `AppIdentity`) —
   https://learn.microsoft.com/en-us/purview/audit-copilot and
   https://learn.microsoft.com/en-us/purview/audit-log-activities#copilot-activities
2. Office 365 Management Activity API reference (`/subscriptions/content`,
   `contentType=Audit.General`, `NextPageUri` pagination header, `contentUri` blob
   retrieval, **start time no more than 7 days in the past**, **24-hour** max query span,
   `/start` to enable a subscription, `ActivityFeed.Read` claim) —
   https://learn.microsoft.com/en-us/office/office-365-management-api/office-365-management-activity-api-reference
3. Microsoft Power Platform CLI command groups (authoritative `pac` group list — there is
   **no** `pac flow` group) —
   https://learn.microsoft.com/power-platform/developer/cli/reference/group
4. Retirement of Office 365 connectors within Microsoft Teams (incoming webhooks;
   progressive rollout completing **May 22, 2026**; new webhook creation blocked since
   August 2024) —
   https://devblogs.microsoft.com/microsoft365dev/retirement-of-office-365-connectors-within-microsoft-teams/
   (also message-center notice MC1181996)
5. Microsoft Graph `Send-MgUserMail` / `Mail.Send` (Test-AlertDelivery email path) —
   https://learn.microsoft.com/en-us/graph/api/user-sendmail

## Verified Correct (no change needed)

- **RecordType 261 = `CopilotInteraction`** filter in both collector scripts — matches the
  authoritative audit schema (source 1).
- **`CopilotEventData` parsing** (`AISystemPlugin[].Name`, `AccessedResources`, `Contexts[].Id`,
  agent identity via `AgentId`/`BotId`/`AppIdentity`) — field names match the documented
  Copilot audit schema (source 1).
- **Office 365 Management API usage** — `subscriptions/content?contentType=Audit.General`,
  `NextPageUri` header pagination, `contentUri` blob fetch, the **24-hour windowing** in
  `New-AgentBaseline.ps1`, and `-Days` `ValidateRange(1,7)` all align with the documented
  7-day/24-hour constraints (source 2).
- **`ActivityFeed.Read` (Application)** permission and `manage.office.com` token audience —
  correct for the Management API; Dataverse token uses `<env>/.default` audience (source 2).
- **Managed-identity-first auth** — IMDS / App Service / `MSI_ENDPOINT` token acquisition is
  attempted before the client-secret fallback, which is marked `# legacy: dev-only` and
  wraps the plaintext secret into a `SecureString`. Consistent with repo auth standard.
- **Dataverse column logical names** — every `$select`/`$filter`/record field
  (`fsi_status`, `fsi_agentid`, `fsi_environmentid`, `fsi_violationtype`, `fsi_resourcename`,
  `fsi_auditrecordid`, `fsi_severity`, `fsi_detectedon`, `fsi_accessdetails`, the
  `fsi_allowed*` arrays) matches `docs/dataverse-schema.md`. No snake_case violations.
- **Option-set values** use 10001+ ranges everywhere (violation type, severity, status,
  zone), matching the schema doc — no 0/1/2 drift.
- **Language rules** — no FSI-prohibited compliance-absolute phrases
  (per `fsi-language-rules.instructions.md`) in any markdown.

## Gaps Found and Fixed

| # | File | Issue | Fix |
|---|------|-------|-----|
| 1 | `docs/troubleshooting.md` | "Export Flow Run Data" prescribed `pac flow list` / `pac flow run list` / `pac flow run show` — **no such `pac` command group exists** (source 3). | Replaced with accurate guidance: portal 28-day run history export, the Power Automate Management connector **List Flow Runs** action to a long-term store, and Dataverse flow-run tables; added FINRA 4511 / SEC 17a-4 retention caveat. |
| 2 | `scripts/Test-AlertDelivery.ps1` | `.NOTES` and runtime `Write-Warning` stated "Teams incoming webhooks retired March 31, 2026" — that specific date is from third-party blogs, not Microsoft. Authoritative retirement is a 2026 progressive rollout completing **May 22, 2026** (source 4). | Updated both occurrences to the authoritative rollout window and noted that new webhook creation has been blocked since August 2024; recommended Power Automate Workflows. |

## Runtime-Only Caveats (cannot be statically verified — confirm in lab)

- **No live tenant:** end-to-end detection (audit query → scope compare → violation create)
  was not executed. Parse-validity and API/permission shapes verified against docs only.
- **`@odata.bind` navigation property:** violation/scope creation binds lookups with the
  attribute logical name (e.g. `fsi_agentscopeid@odata.bind`, `fsi_owner@odata.bind`).
  Dataverse `@odata.bind` expects the **single-valued navigation property name**, which
  usually matches the lookup schema name. Confirm against the deployed entity metadata on
  first write; adjust if the relationship navigation name differs.
- **`AccessedResources` sub-field shape:** the scripts probe `Type`, `SiteUrl`, `Name`,
  `Id/Url` defensively, but the authoritative schema example exposes `Action`/`ID`. Real
  Dataverse-table / external-API detection coverage depends on the actual payload; validate
  with real CopilotInteraction events and extend property probing if needed.
- **Subscription bootstrap:** `New-AgentBaseline.ps1` calls `/subscriptions/start`, but
  `Invoke-DriftScan.ps1` does not. If no active `Audit.General` subscription exists, the
  first scan can return `AF20024`. Start the subscription once before initial scanning (the
  troubleshooting guide documents this).
- **Sovereign IC cloud (eaglex):** the client-secret fallback maps the IC endpoint to the
  `login.microsoftonline.us` authority. The IC (eaglex) login authority may differ; out of
  scope for a commercial-cloud lab — verify before any IC deployment.

## Lab-Readiness Assessment

**Ready for lab validation.** All three scripts parse cleanly under PowerShell 7 with zero
errors, the auth model is managed-identity-first, Dataverse column references and option-set
values match the schema, and every load-bearing API/permission/feature claim is confirmed
against authoritative Microsoft documentation. Two documentation/accuracy defects (invalid
`pac flow` CLI commands, stale Teams-webhook retirement date) were corrected. Remaining items
are genuine runtime-only checks (live audit payloads, `@odata.bind` navigation names,
subscription bootstrap) that require a tenant and are documented above for the lab operator.
