# Lab Validation Report — Content Moderation Monitor

> **Solution:** content-moderation-monitor · **Version:** v1.1.2
> **Validated:** 2026-06-04 · **Mode:** Static (no live tenant)
> **Controls:** 1.27 (primary — AI Agent Content Moderation Enforcement), 1.8 (complementary — Runtime Protection and External Threat Detection)

## Purpose

Per-agent validation that Copilot Studio agents meet their governance zone's
minimum content-moderation level. The monitor enumerates Power Platform
environments, reads each bot's moderation configuration from Dataverse, compares
against zone minimums, and persists immutable evidence (validation history,
violations, baselines) for regulatory examination. A supplementary Python script
correlates persisted violations with Microsoft Purview unified audit log signals.

## What Was Checked

| Area | Method | Result |
|------|--------|--------|
| Python parse validity | `python -m py_compile` on all 6 `scripts/*.py` | PASS |
| PowerShell parse validity | `Parser::ParseFile` on all 13 `*.ps1`/`*.psm1` | PASS (0 errors) |
| Language rules | grep for the four prohibited overclaim phrases per `fsi-language-rules` (excl. CHANGELOG) | PASS (0 hits) |
| Dataverse column naming | grep for snake_case `fsi_*_*` outside known prefixes; cross-check vs `create_dataverse_schema.py` | PASS — all references use logical names |
| Option-set value drift | Verified `fsi_acv_zone` = 100000000+ in docs and code | PASS |
| Graph audit API surface | Authoritative Microsoft Learn verification | **1 bug found and fixed** |
| Copilot Studio moderation naming | Authoritative Microsoft Learn verification | PASS — README scope notes accurate |

## Authoritative Sources Cited

1. **Create auditLogQuery (Graph)** — `POST /security/auditLog/queries`; permission `AuditLogsQuery.Read.All` (Application). Least-privileged service-scoped variants (e.g. `AuditLogsQuery-CRM.Read.All`) also supported.
   https://learn.microsoft.com/graph/api/security-auditcoreroot-post-auditlogqueries?view=graph-rest-1.0
2. **auditLogQuery resource** — confirms body properties `filterStartDateTime`, `filterEndDateTime`, `recordTypeFilters`, `operationFilters`; `status` enum (`notStarted`/`running`/`succeeded`/`failed`/`cancelled`); `records` navigation.
   https://learn.microsoft.com/graph/api/resources/security-auditlogquery?view=graph-rest-1.0
3. **auditLogRecordType enum** — canonical member list. `MicrosoftTeams` and `PowerPlatformServiceActivity` are valid; **`CopilotInteraction` and `PowerPlatform` are NOT members.**
   https://learn.microsoft.com/graph/api/resources/security-auditlogrecordtype?view=graph-rest-1.0
4. **Copilot in the audit log** — Copilot interactions log with **Operation `CopilotInteraction`, RecordType 261**.
   https://learn.microsoft.com/purview/audit-copilot
5. **Copilot Studio content moderation** — moderation levels range from **Lowest** to **Highest** (not Low/Medium/High).
   https://learn.microsoft.com/microsoft-copilot-studio/nlu-boost-node ·
   https://learn.microsoft.com/microsoft-copilot-studio/knowledge-copilot-studio

## Gaps Found & Fixes Applied

### FIX 1 — Invalid Graph `recordTypeFilters` values (Major; runtime-breaking)

`correlate_purview_events.py` defined
`COPILOT_RECORD_TYPES = ["CopilotInteraction", "MicrosoftTeams", "PowerPlatform"]`
and passed them as `recordTypeFilters` to the Graph `auditLogQuery` POST.

- `recordTypeFilters` is a typed `auditLogRecordType` enum collection (source 3).
- `CopilotInteraction` is **not** an enum member — it is an *operation* name (RecordType 261, source 4).
- `PowerPlatform` is **not** an enum member — valid Power Platform members are `PowerPlatformServiceActivity`, `PowerPlatformAdminEnvironment`, `PowerPlatformAdminDlp`, etc.

Passing unknown enum members would cause the Graph API to reject the query, breaking the correlation pipeline at runtime.

**Fix:** Added `operation_filters` support to `create_audit_log_query` and switched the call to
`operationFilters: ["CopilotInteraction"]`, the documented way to target Copilot interaction events.
The record-type filter is intentionally omitted because `auditLogQuery` filters are AND-combined and the
Graph enum exposes no Copilot record type. README correlation description and CHANGELOG updated to match.

### Verified-correct (no change needed)

- **Moderation label normalization.** README "Scope and Limitations" already states Copilot Studio uses
  **Lowest–Highest** and that CMM maps `Lowest→Low` / `Highest→High` onto its three-level evidence scale.
  Verified accurate against source 5. `Get-ExpectedModerationLevel.ps1` and `Get-BotModerationLevel`
  implement this mapping consistently.
- **Graph permission claim.** `AuditLogsQuery.Read.All` (Application) is a valid permission for the audit
  query API (source 1). README now also notes the least-privileged service-scoped variants.
- **Dataverse schema references.** All `$select`/`$filter` columns across scripts and docs match
  `create_dataverse_schema.py` logical names (e.g. `fsi_actuallevel`, `fsi_environmentguid`,
  `fsi_validationtime`); the explicit singular entity set `fsi_moderationvalidationhistory` and the
  auto-plural `fsi_moderationviolations` are used correctly (consistent with `.ralph-config.json`).
- **Auth posture.** Managed-identity-first ordering documented; client-secret paths carry the
  `# legacy: dev-only` marker; `Get-AzAccessToken` SecureString handling is present in
  `Connect-EnvironmentDataverse.ps1` and `CMMClient.psm1`.

## Runtime-Only Caveats (not verifiable without a live tenant)

1. **Undocumented moderation source field.** The monitor parses the unstructured `bot.configuration`
   JSON for several candidate keys (`ContentModeration`, `contentModeration`, ...). Copilot Studio exposes
   no documented public field for the agent-default moderation level. If the internal key changes, agents
   report `Unknown` — the scan emits a warning and should be treated as **unverified, not compliant**.
   This is honestly documented in the README and TROUBLESHOOTING.md. Confirm against a live agent before
   relying on results.
2. **Correlation user-matching quality.** `correlate_purview_events.py` matches moderation-violation
   `ownerid` (a Dataverse systemuser GUID = the scan operator) against audit `UserId` (a UPN = the runtime
   end user). These identifiers differ in both type and subject, so match yield will be low; the script is
   positioned as supplementary enrichment, not a primary 1.8 control. A future enhancement could resolve
   `ownerid → UPN` via the `User.Read.All` grant and correlate on end-user identity. Validate empirically.
3. **AND-combined audit filters.** With `operationFilters: ["CopilotInteraction"]` only, the query returns
   Copilot interaction events in the window. Verify volume/throttling behavior on a production-sized tenant.

## Lab-Readiness Assessment

**READY for lab deployment** with the documented caveats. All scripts parse and compile, schema
references are internally consistent, language and naming conventions pass, and the one runtime-breaking
Graph enum defect has been corrected and grounded in authoritative Microsoft documentation. The
remaining items are inherent runtime/data-quality characteristics that require a live tenant to exercise
and are already disclosed to operators in the README and troubleshooting guide.
