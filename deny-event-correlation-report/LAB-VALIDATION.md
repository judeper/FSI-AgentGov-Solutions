# Lab Validation — Deny Event Correlation Report

> **Validation date:** 2026-06-04
> **Solution version:** v2.0.4 (Unreleased changes pending)
> **Validation type:** Static — parse-validity, authoritative-source verification, and
> documentation completeness. No live tenant was used; runtime behavior against real
> Purview/Defender/Application Insights data was not exercised.

## Purpose and Controls

Daily operational reporting that correlates "deny / no-content-returned" events for
Microsoft 365 Copilot and Copilot Studio across four Microsoft data sources (Purview
Unified Audit Log, Purview DLP, Application Insights RAI telemetry, and optional
Defender CloudAppEvents). Supports compliance evidence for **Control 1.5** (DLP and
sensitivity labels), **Control 1.7** (comprehensive audit logging), **Control 1.8**
(runtime protection and external threat detection), and **Control 3.4** (incident
reporting). Regulatory alignment: helps support FINRA 4511, SEC 17a-3/17a-4, GLBA
501(b), and supervisory guidance under FINRA 24-09 / 25-07 and OCC 2011-12 / Fed SR
11-7 (the solution is one ancillary record source, not a complete compliance program).

## What Was Checked

| Area | Method | Result |
|------|--------|--------|
| PowerShell parse validity (6 scripts) | `Parser::ParseFile` | All 6 parse with **zero** errors |
| `Search-UnifiedAuditLog` status | Microsoft Learn + Azure/M365 messaging | Cmdlet is **current**, not retired; correct production extractor |
| Graph `runHuntingQuery` endpoint + permission | Microsoft Learn (graph-rest-1.0) | Script endpoint and scope **match** the GA contract |
| Defender `CloudAppEvents` schema | Microsoft Learn (advanced hunting schema) | `RawEventData` is `dynamic` raw JSON; `ThreatCategory` correctly treated as tenant-verify |
| Application Insights query API-key retirement date | Microsoft release communications | Date was **outdated** (March 31, 2026) — corrected to September 30, 2026 |
| `Get-AzAccessToken -ResourceUrl … -AsSecureString` | Az.Accounts 5.x behavior | Correct SecureString contract, defensive plaintext fallback present |
| Language rules (no compliance-overclaim phrasing) | grep across solution | **Zero** violations |
| KQL parse-coherence (5 query files) | Manual review | Coherent; ingestion-pattern caveats already documented |
| DLP audit filter (`Export-DlpCopilotEvents.ps1`, `dlp-copilot-matches.kql`) | Microsoft Learn (Management Activity API schema) | **Second-pass fix:** `DlpRuleMatch` is an Operation, not a RecordType — moved to `-Operations` / KQL `Operation`; removed wrong "Numeric equivalent: 55" comment (55 = SharePointContentTypeOperation) |

## Authoritative Sources Cited

1. **security: runHuntingQuery (Microsoft Graph v1.0)** — confirms
   `POST /security/runHuntingQuery` is GA and the least-privileged permission is
   `ThreatHunting.Read.All` (delegated and application).
   <https://learn.microsoft.com/graph/api/security-security-runhuntingquery?view=graph-rest-1.0>
2. **CloudAppEvents (Defender XDR advanced hunting schema)** — confirms `RawEventData`
   is a `dynamic` column carrying raw source JSON (so `ThreatCategory` is not a
   first-class column and must be verified per tenant).
   <https://learn.microsoft.com/defender-xdr/advanced-hunting-cloudappevents-table>
3. **Search-UnifiedAuditLog (Exchange Online PowerShell)** — the cmdlet remains the
   supported unified-audit extractor; the retired cmdlets are
   `Search-MailboxAuditLog` / `New-MailboxAuditLogSearch` (retired end-2025), not
   `Search-UnifiedAuditLog`.
   <https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog>
4. **Azure Update — "Retirement: Transition to Entra ID … to query data from Azure
   Monitor Application Insights by September 30, 2026"** (Microsoft Release
   Communications; modified 2026-04-21). States: *"Previously announced to be retired
   March 31, 2026. We have extended the retirement date to September 30, 2026."*
   <https://www.microsoft.com/releasecommunications/api/v2/Azure/rss/transition-to-azure-ad-to-query-data-from-azure-monitor-application-insights-by-31-march-2026>
5. **Microsoft Entra authentication for Application Insights** — Entra ID is the
   supported query authentication path (the method the extractor already uses).
   <https://learn.microsoft.com/azure/azure-monitor/app/azure-ad-authentication>

## Gaps Found and Fixes Applied

### Fixed — outdated Application Insights API-key retirement date (documentation)

The docs and one script header stated the `x-api-key` query path was deprecated/removed
on **March 31, 2026** — a date that is now in the past and, per Microsoft, no longer the
actual retirement date. Microsoft **extended** the retirement to **September 30, 2026**.
Statements such as "no longer functional as of March 31, 2026" were factually incorrect
as of this validation (the API key still functions until September 30, 2026).

Corrected occurrences in:
- `docs/prerequisites.md` (deprecation table row, retirement warning, timeline table)
- `docs/troubleshooting.md` (issue #2 banner and historical diagnostic comment)
- `docs/architecture.md` (authentication table row)
- `scripts/Export-RaiTelemetry.ps1` (migration header note)

The wording now states the September 30, 2026 retirement and references the original
March 31, 2026 date only as historical context. **No runtime code path changed** —
`Export-RaiTelemetry.ps1` already authenticates with Entra ID via `Connect-AzAccount` /
`Get-AzAccessToken`, so it is unaffected by the API-key retirement regardless of date.

### Verified — no change required

- **Graph Defender extractor** (`Export-DefenderCopilotEvents.ps1`): uses the GA
  `https://graph.microsoft.com/v1.0/security/runHuntingQuery` endpoint with
  `ThreatHunting.Read.All`, matching the authoritative v1.0 contract.
- **CopilotInteraction extractor** (`Export-CopilotDenyEvents.ps1`):
  `Search-UnifiedAuditLog -RecordType CopilotInteraction` is correct —
  `CopilotInteraction` (AuditLogRecordType 261) is a valid `AuditRecordType`
  enum member. The Graph `/security/auditLog/queries` beta is accurately
  described as a not-yet-production migration path.
- **DLP Workload literals** `Copilot` / `MicrosoftCopilotStudio` are used consistently
  across script and KQL (the incorrect `MicrosoftCopilot` literal was already removed in
  v2.0.2).
- **KQL ingestion caveats**: the Log Analytics queries already document the
  `OfficeActivity` flattening limitation and point operators to the PowerShell
  extractors as the recommended path.
- **Language rules**: no prohibited compliance-overclaim phrasing.

## Runtime-Only Caveats (not verifiable without a live tenant)

These items are correctly caveated in the solution docs/scripts and require tenant-side
validation before production reliance:

1. **Defender `CloudAppEvents` Copilot fields** — `ActionType == "CopilotInteraction"`
   and `RawEventData.ThreatCategory` values (`PromptInjection`, `Jailbreak`, `XPIA`) are
   raw-event-shaped and tenant/licensing dependent. Validate in your tenant's Advanced
   Hunting before relying on results. (Already flagged in `cloud-app-events.kql` and the
   script `.NOTES`.)
2. **CopilotInteraction audit deny indicators** — presence of
   `AccessedResources[].Status == "failure"` / `PolicyDetails` depends on actual Copilot
   usage and DLP policy configuration; cannot be exercised offline.
3. **Application Insights ContentFiltered telemetry** — depends on per-agent App
   Insights configuration in Copilot Studio and on the resource being classic
   (`customEvents`) vs workspace-based (`AppEvents`). The normalization block handles
   both shapes, but live emission was not observed.
4. **Exchange Online unattended auth** — managed identity (`Exchange.ManageAsApp`) and
   certificate app-only paths were not exercised against a tenant.
5. **Graph `runHuntingQuery` Timespan vs in-query filter** — the extractor embeds the
   date window in the KQL `where Timestamp between(...)` clause; the API applies the
   shorter of the query filter and the default 30-day timespan, which is the intended
   1-day window.

## Lab-Readiness Assessment

**Lab-ready (static validation passed).** All six PowerShell scripts parse cleanly, the
external API contracts the scripts depend on (Graph `runHuntingQuery`,
`Search-UnifiedAuditLog`, Application Insights query API, Az.Accounts token acquisition)
were verified against authoritative Microsoft sources, and the one factual drift found
(an outdated, now-past retirement date) was corrected. Remaining open items are
genuinely runtime-only and require a licensed tenant with Copilot, DLP, App Insights,
and (optionally) Defender for Cloud Apps to exercise end-to-end. No blocking issues
were found for lab deployment.
