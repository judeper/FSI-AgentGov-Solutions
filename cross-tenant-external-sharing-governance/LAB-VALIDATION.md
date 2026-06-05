# Lab-Readiness Validation — Cross-Tenant External Sharing Governance

> **Solution version:** v1.1.0
> **Validation date:** 2026-06-04
> **Validation type:** Static (no live tenant) — parse-validity, authoritative-source
> verification of every API/permission/feature assertion, and documentation completeness.

## Purpose and controls

Three-layer cross-tenant access governance for Power Platform AI agents in FSI
environments: **Layer 1** Power Platform Tenant Isolation, **Layer 2** Microsoft
Entra Cross-Tenant Access (CTA) policies, **Layer 3** Copilot Studio agent shares.
Primary framework controls: **1.1, 1.18, 2.1, 2.8, 1.7, 1.11**.

## What was checked

| Area | Method | Result |
|------|--------|--------|
| Python scripts (5) | `python -m py_compile` | All compile cleanly |
| PowerShell scripts (3) | `Parser::ParseFile` zero-error check | All parse cleanly |
| Dataverse schema docs | Regenerated via `create_ctsg_dataverse_schema.py --output-docs` | No drift (git clean) |
| Column references in scripts | Cross-checked against `docs/dataverse-schema.md` (source of truth) | All logical names correct |
| Language rules | Grep for prohibited compliance-overclaim phrases (excl. CHANGELOG) | Zero violations |
| Graph CTA endpoints/permissions/properties | Microsoft Learn | Confirmed authentic |
| Power Platform tenant isolation cmdlet | Microsoft Learn | Confirmed authentic |
| Managed Environment detection + sharing properties | Microsoft Learn | **One defect found & fixed** |
| Power Platform connector logical IDs | Microsoft Learn (prior council fix re-verified) | Correct (V2 / HTTP-with-Entra) |

## Authoritative sources cited

1. crossTenantAccessPolicyConfigurationDefault / Partner resource types, methods, and
   properties (`b2bCollaborationInbound/Outbound`, `b2bDirectConnectInbound/Outbound`,
   `inboundTrust`, `automaticUserConsentSettings`, `isServiceProvider`,
   `isInMultiTenantOrganization`, `tenantRestrictions`) —
   https://learn.microsoft.com/graph/api/resources/crosstenantaccesspolicyconfigurationpartner
   and https://learn.microsoft.com/graph/api/resources/crosstenantaccesspolicyconfigurationdefault
2. Cross-tenant access policy Graph permissions `Policy.Read.All` and
   `Policy.ReadWrite.CrossTenantAccess` — Microsoft Graph permissions reference and the
   crossTenantAccessPolicy API pages (confirmed both present).
3. Power Platform tenant isolation cmdlet `Get-PowerAppTenantIsolationPolicy` —
   https://learn.microsoft.com/power-platform/admin/cross-tenant-restrictions
   (Microsoft.PowerApps.Administration.PowerShell).
4. Managed Environments protection level (`Standard` = enabled) via `pac admin
   set-governance-config --protection-level` —
   https://learn.microsoft.com/power-platform/developer/cli/reference/admin
5. **Managed Environments "Limit sharing" agent-sharing properties** —
   https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits
   (authoritative property names: `bot-limitSharingMode`, `bot-maxLimitUserSharing`,
   `bot-authoringSharingDisabled`; values `noLimit` / `ExcludeSharingToSecurityGroups`,
   `-1` = unlimited).
6. `Get-AzAccessToken` SecureString behavior (Az.Accounts) —
   https://learn.microsoft.com/powershell/azure/manage-secrets-with-azure-powershell
   (confirms the `-AsSecureString` pattern already pinned via `#Requires Az.Accounts 2.17.0`).

## Gaps found and fixes applied

### Scripts

- **`Scan-ManagedEnvBotSharingBaseline.ps1` — invented governance property names
  (functional defect).** The three baseline checks read
  `extendedSettings.botSharingAccessControl`, `…botSharingSharingApproval`, and
  `…botSharingMaxShareLimit`. None of these exist in the documented Managed
  Environments `governanceConfiguration` schema, so every property lookup returned
  `$null` and the scanner would flag **every** environment non-compliant on all
  three checks against a real tenant (false positives). Replaced with the
  authoritative agent-sharing properties:
  - `bot-limitSharingMode` — flagged when unset or `noLimit` (expected
    `ExcludeSharingToSecurityGroups`), compared case-insensitively because
    Microsoft docs show mixed casing.
  - `bot-authoringSharingDisabled` — flagged when not `True` (editor-level agent
    sharing should be disabled). Replaces the non-existent "sharing approval
    workflow" property.
  - `bot-maxLimitUserSharing` — flagged when `<= 0` or unset (`-1` = unlimited).
  The `BaselinePolicy` parameter default changed from the undocumented
  `Restricted` to the documented enum `ExcludeSharingToSecurityGroups`; synopsis,
  parameter help, and the emitted `BotSharingConfig` keys were updated to match.

### Verified correct (no change required)

- **Graph Layer 2** — `/policies/crossTenantAccessPolicy`, `/default`, and
  `/partners` endpoints, pagination via `@odata.nextLink`, and all partner/default
  property reads are authentic and correctly versioned (`v1.0`).
- **Layer 1 BAP endpoints** — `…/scopes/admin/tenantSettings` and
  `…/crossTenantConnectionAllowPolicy` (api-version `2020-10-01`) with token
  audience `https://service.powerapps.com/`. These remain heavily caveated in-script
  and in `DELIVERY-CHECKLIST.md`; the documented validation path
  (`Get-PowerAppTenantIsolationPolicy`) is correct and present in prerequisites.
- **Auth** — managed-identity-first across all three PowerShell scripts;
  `Get-AzAccessToken -AsSecureString` + `ConvertFrom-SecureString -AsPlainText` with
  `#Requires Az.Accounts 2.17.0`; the single `ClientSecret` branch is marked
  `# legacy: dev-only`.
- **Connector logical IDs** — `shared_powerplatformforadmins` (V2 admin),
  `shared_webcontents` (HTTP with Entra ID), `shared_commondataserviceforapps`,
  `shared_approvals`, `shared_teams`, `shared_office365` — all correct.
- **Dataverse column logical names** and **option-set values** (100000000-based,
  with the documented `fsi_acv_zone` 0-based carve-out) — consistent across schema
  script, generated schema doc, scripts, and flow docs.

### Documentation / dependencies

- No documentation referenced the old invented property names (confirmed by grep);
  no further doc edits required.
- `requirements.txt`, required PowerShell modules
  (`Az.Accounts`, `Microsoft.PowerApps.Administration.PowerShell`), Graph
  permissions, and Entra roles in `docs/prerequisites.md` are complete and match the
  scripts.

## Runtime-only caveats (cannot be validated statically)

- **Layer 1 BAP response shape** — exact property name for the isolation flag
  (`isolationEnabled` vs `tenantIsolationEnabled`) and the allow-list `value[]`
  schema must be confirmed against a live tenant response; the script already
  detects and reports schema mismatches and adds delivery-checklist items.
- **Managed Environment `extendedSettings` payload** — whether `bot-*` keys are
  present depends on whether the "Limit sharing" agent controls were ever
  configured in the environment; absent keys are treated (correctly) as
  non-compliant. The casing returned by the BAP API (`excludeSharingToSecurityGroups`
  vs `ExcludeSharingToSecurityGroups`) is handled case-insensitively.
- **Dataverse entity-set pluralization and option-set integers** — confirm against
  the deployed solution XML before activating flows, as already documented in the
  script `.NOTES` and `DELIVERY-CHECKLIST.md`.

## Final lab-readiness assessment

**Lab-ready.** All scripts parse/compile; documentation is internally consistent and
schema-aligned; every external API, permission, and feature assertion was verified
against authoritative Microsoft sources. One genuine functional defect (the Managed
Environment bot-sharing property names) was found and corrected. Remaining
unverifiable items are inherent live-tenant response-shape confirmations, which the
scripts already surface as delivery-checklist actions rather than silent assumptions.

## Second-Pass Command-Existence Re-Verification (2026-06-05)

An independent second-pass audit re-derived every invoked command, cmdlet, CLI verb, REST endpoint and api-version, Dataverse entity set / logical column / option-set, and module against Microsoft Learn, with a sharpened focus on confirming each surface exists and will run in a live lab. Microsoft Graph cross-tenant access endpoints (crossTenantAccessPolicy / default / partners on v1.0) and all consumed properties, Get-AzAccessToken, Get-PowerAppTenantIsolationPolicy, the BAP governanceConfiguration call, and all Dataverse entity sets / columns / option-sets were confirmed. Two BAP admin endpoints remain operator-confirmation items but are try/catch-guarded. No corrections required.

