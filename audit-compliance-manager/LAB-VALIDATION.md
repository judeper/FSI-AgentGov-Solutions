# Lab Validation Report — Audit Compliance Manager (ACM)

> **Solution:** audit-compliance-manager · **Version:** v1.0.5 (Unreleased changes pending)
> **Primary control:** 1.7 (Audit logging) · **Tier:** 2
> **Validation type:** Static (no live tenant) — parse-validity, authoritative-source verification, documentation completeness
> **Date:** 2026-06-04

## Purpose and scope

ACM is a unified audit-compliance solution merging the Audit Configuration
Validator (ACV) and Audit Logging Compliance Automation (ALCA). It validates
tenant- and environment-level audit configuration, detects compliance gaps,
remediates non-compliant Power Platform environments by enabling Dataverse
auditing, and exports SHA-256-hashed evidence. It supports compliance with
FINRA Rule 4511, SEC Rule 17a-3/17a-4, GLBA 501(b), and SOX Section 404
record-keeping requirements (no single control satisfies a regulation in
isolation).

This pass brought the solution to a lab-ready steady state through static
validation against authoritative Microsoft sources. The solution had already
passed several prior council reviews (see CHANGELOG v1.0.1–v1.0.5), so it
entered this pass in strong shape; findings were limited to documentation drift
and a forward-looking platform note.

## What was checked

| Area | Method | Result |
|------|--------|--------|
| PowerShell parse validity (changed `.ps1`) | `Parser::ParseFile` (0 errors) | Pass |
| Python compile validity (`.py`) | `python -m py_compile` | Pass |
| Language rules (no absolute compliance-guarantee phrasing) | grep across solution (excl. CHANGELOG history) | Pass — 0 hits |
| Dataverse column naming (logical names, no inter-word underscores) | grep `fsi_*_*` + schema cross-check | Pass — all hits are option-set / connection-reference / alternate-key names or intentional "invalid" test fixtures |
| Option-set values documented as `100000000+` (not `0/1/2`) | inspect `private/Get-ValidationResults.ps1`, `Write-ValidationResult.ps1` | Pass |
| Audit cmdlet currency (`Search-UnifiedAuditLog`, `Get-AdminAuditLogConfig`) | Microsoft Learn | Pass — current |
| Managed-identity-first auth + token audiences | inspect `AuditComplianceHelpers.psm1` | Pass |
| Module version consistency (`ExchangeOnlineManagement`) | grep across solution | **Fixed** — drift `3.7.0` vs `3.0.0` |
| Graph Audit Query API permission name | Microsoft Learn | **Corrected during drafting** — `AuditLogsQuery.Read.All` |

## Authoritative sources cited (exact URLs)

- Turn auditing on or off (`Get-AdminAuditLogConfig | FL UnifiedAuditLogIngestionEnabled`, `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true`, Audit Logs role requirement, on-by-default) — https://learn.microsoft.com/purview/audit-log-enable-disable
- `Search-UnifiedAuditLog` reference (current cmdlet; replacement for retiring mailbox audit cmdlets) — https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog
- Microsoft Graph `auditLogQuery` resource + `List auditLogQueries` (permission `AuditLogsQuery.Read.All` and workload-scoped variants; `GET /security/auditLog/queries`) — https://learn.microsoft.com/graph/api/resources/security-auditlogquery
- Azure Automation managed identity token endpoint (`IDENTITY_ENDPOINT` / `X-IDENTITY-HEADER`, `api-version=2019-08-01`) — https://learn.microsoft.com/azure/automation/enable-managed-identity-for-automation
- Microsoft Graph `users: sendMail` (requires `Mail.Send`) — https://learn.microsoft.com/graph/api/user-sendmail

All cited Learn URLs were confirmed to return HTTP 200 during this pass.

## Authoritative findings (verification detail)

1. **`Search-UnifiedAuditLog` is current, not deprecated.** The "this cmdlet will
   be deprecated" note in the Exchange audit docs refers to the mailbox-specific
   cmdlets (`Search-MailboxAuditLog`, `New-MailboxAuditLogSearch`), which point
   operators *to* `Search-UnifiedAuditLog`. ACM uses only
   `Search-UnifiedAuditLog`, so it is unaffected. Mailbox-specific cmdlets are
   retiring at the end of 2025.
2. **`Get-AdminAuditLogConfig` remains the documented enablement check.** Microsoft
   Learn still shows `Get-AdminAuditLogConfig | Format-List UnifiedAuditLogIngestionEnabled`
   (Exchange Online PowerShell) as the verification method, and
   `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true` to enable —
   matching the scripts. The script comment that the Security & Compliance
   PowerShell variant returns `False` for this property is a correct, important
   caveat.
3. **Graph Audit Query API permission corrected.** The modern Graph audit path
   uses `AuditLogsQuery.Read.All` (plus workload variants like
   `AuditLogsQuery-Entra.Read.All`) — **not** `AuditLog.Read.All` (a distinct
   directory-audit permission). The initial README draft was corrected before
   commit.
4. **Managed-identity auth verified.** `Get-ManagedIdentityToken` uses the Azure
   Automation IMDS endpoint with `api-version=2019-08-01`; the Dataverse token
   audience is the environment org URL and the Graph token audience is
   `https://graph.microsoft.com` for `sendMail` — correct audiences per service.

## Gaps found and fixes applied

### Fixed in this pass

- **`ExchangeOnlineManagement` version drift (documentation/consistency).** Every
  `#Requires` gate enforces `3.0.0` and the README runtime table says `3.0+`, but
  NOTES prose, the install-hint error message in
  `private/Connect-AuditServices.ps1`, `SOLUTION-DOCUMENTATION.md` (2 places), and
  `docs/flow-setup.md` (3 places) said `3.7.0`. A lab operator following the error
  message would install a stricter minimum than the code enforces. Aligned all
  prose down to `3.0.0`/`3.0+` to match the authoritative `#Requires` gate. No
  cmdlet/parameter used by ACM requires 3.7.0.
- **Audit-access modernization note added.** New README "Platform Update Notes"
  subsection records the `Search-UnifiedAuditLog` vs Graph `auditLogQuery`
  distinction, the retiring mailbox cmdlets (not used here), and the recommended
  future migration path — with authoritative citations.

### Not changed (verified correct as-is)

- Audit cmdlets and parameters, mailbox-audit inverted-logic handling
  (`AuditDisabled`), canary-event dual-validation, Purview retention via
  `Get-UnifiedAuditLogRetentionPolicy` / `New-UnifiedAuditLogRetentionPolicy`,
  managed-identity-first auth, option-set values, Dataverse logical names, and
  the documented certificate/MSAL.PS fallbacks (already flagged as
  dev-only/legacy with a pinned `4.37.0` and deprecation note).
- `manifest.yaml` was **not** modified.

## Runtime-only caveats (cannot be statically verified)

- Live behavior of `Search-UnifiedAuditLog` canary retrieval depends on
  tenant-specific audit ingestion lag (script allows a configurable grace period
  up to 24h).
- Actual unified audit log **retention** is license-bounded (Audit Standard
  180 days for records on/after 2023-10-17; Audit Premium/E5 1 year default; 10
  years with the add-on). The solution flags shortfalls but cannot extend
  retention beyond licensing — documented accurately in README.
- Managed-identity role assignments (Power Platform Admin, Exchange Online Admin,
  `Mail.Send`, Dataverse application user) must exist in the target tenant;
  presence cannot be confirmed without a live environment.
- Dataverse table creation, alternate-key upsert behavior, and Power Automate
  approval flows require a live environment to exercise end-to-end.

## Lab-readiness assessment

**Lab-ready.** All changed scripts parse cleanly, all Python compiles, there are
zero regulatory-language violations, Dataverse naming and option-set values are
correct, and the audit APIs/cmdlets/permissions in scripts and docs are verified
against current authoritative Microsoft sources. The only corrections needed were
documentation-level (module-version drift) plus an additive forward-looking
platform note. Remaining unknowns are inherent runtime/tenant dependencies that
require a live environment and are documented above.
