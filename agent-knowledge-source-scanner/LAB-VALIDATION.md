# Lab Validation — Agent Knowledge Source Scanner

> **Validation type:** Static (no live tenant). Parse-validity + authoritative Microsoft source verification + documentation completeness.
> **Date:** 2026-06-04
> **Solution version at validation:** v1.1.2 (+ `[Unreleased]` doc/permission corrections)

## Purpose and controls

Item-level permission scanning for SharePoint libraries that back Copilot Studio agent
knowledge sources. Surfaces files/folders shared more broadly than an agent's intended
audience (Anyone links, external/guest grants, org-wide links, sensitivity-label
mismatches) and produces a risk-scored CSV.

| Control | Pillar | Relationship |
|---------|--------|--------------|
| 4.8 | SharePoint | Primary — item-level permission scanning for agent knowledge sources |
| 1.4 | Security | Related — data boundary enforcement |
| 1.5 | Security | Related — DLP and sensitivity labels |

Regulatory context: GLBA 501(b) safeguards, FINRA Rule 4511 record-keeping, SEC 17a-3/4
retention of access-review evidence.

## What was checked

- **Parse validity** of both PowerShell scripts (`Parser::ParseFile`, zero errors).
- **Language rules** — grep for the prohibited absolute-compliance phrasing across
  Markdown (excluding CHANGELOG history): zero hits.
- **Authoritative verification** of every Microsoft Graph API, permission, batching, and
  PnP.PowerShell authentication claim in the scripts and docs.
- **Dataverse column naming** — N/A. This solution has no Dataverse integration; output is
  CSV-only (confirmed in `.ralph-config.json`). No option sets or logical names to verify.
- **No Power Platform runtime artifacts** — confirmed; solution ships scripts + docs +
  one JSON config template only.

## Authoritative sources cited

| Claim (in code/docs) | Verified against | Result |
|----------------------|------------------|--------|
| `GET /drives/{driveId}/items/{itemId}/permissions` is **v1.0** and returns `permission` resources | [List permissions on a driveItem](https://learn.microsoft.com/graph/api/driveitem-list-permissions?view=graph-rest-1.0) | ✅ Confirmed |
| Least-privileged permission for that endpoint | [List permissions — Permissions](https://learn.microsoft.com/graph/api/driveitem-list-permissions?view=graph-rest-1.0#permissions) | ✅ App: `Files.Read.All`; Delegated: `Files.Read`; higher: `Sites.Read.All`. **`Group.Read.All` not listed** |
| `grantedToIdentitiesV2` resolves specific-people (link `scope: users`) grants | [permission resource type](https://learn.microsoft.com/graph/api/resources/permission?view=graph-rest-1.0) | ✅ Confirmed (Collection of `sharePointIdentitySet`, for link-type permissions) |
| `link.scope` values handled (`anonymous`, `organization`, `users`) | [sharingLink resource type](https://learn.microsoft.com/graph/api/resources/sharinglink?view=graph-rest-1.0) | ✅ Confirmed; `existingAccess` also valid (falls to script's `default`/`OtherLink` branch) |
| JSON batching hard cap of **20** requests; throttled sub-requests return `429` | [Combine multiple HTTP requests using JSON batching](https://learn.microsoft.com/graph/json-batching) | ✅ Confirmed ("limited to 20 individual requests") |
| `Connect-PnPOnline -ManagedIdentity` with `-UserAssignedManagedIdentityClientId` / `ObjectId` / `AzureResourceId` | [Connect-PnPOnline](https://pnp.github.io/powershell/cmdlets/Connect-PnPOnline.html) | ✅ Confirmed — exact parameter sets used by the script |
| PnP.PowerShell 3.x requires PowerShell **7.4+** and **.NET 8**; `Get-PnPAzureADGroupMember` → `Get-PnPEntraIDGroupMember` | PnP.PowerShell 3.0 release notes / [cmdlet docs](https://pnp.github.io/powershell/cmdlets/) | ✅ Confirmed |
| Multi-tenant PnP app retired Sept 2024; interactive auth needs tenant-specific app via `Register-PnPEntraIDAppForInteractiveLogin` | PnP.PowerShell docs / 3.x migration guidance | ✅ Confirmed (consistent with vendor guidance) |
| `Get-AzAccessToken` returns `.Token` as `SecureString` (Az.Accounts 5.x default) | [Get-AzAccessToken](https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken) | ✅ Confirmed; `-AsSecureString` / `-ResourceTypeName MSGraph` are current |

## Gaps found and fixes applied

### 1. Over-claimed Graph permission (`Group.Read.All`) — security/least-privilege
- **Gap:** README "Microsoft Graph Permissions" table and `Invoke-GraphPermissionScan.ps1`
  `.NOTES` listed `Group.Read.All` as required for the Graph scanner. The
  list-permissions endpoint requires only `Files.Read.All` (app) / `Files.Read`
  (delegated); `Sites.Read.All` is a higher-privileged alternative. The Graph scanner
  never calls a group-membership endpoint — it reads group display names inline from the
  `grantedToV2` / `grantedToIdentitiesV2` facets of each permission. For a governance
  solution that itself enforces least privilege, documenting an unneeded directory-wide
  read scope was a contradiction.
- **Fix:** Rewrote the README permissions table to mirror the authoritative least-privileged
  set, added the source link, and explicitly stated `Group.Read.All` is not required (group
  names returned inline). Updated the script `.NOTES` to match. The PnP scanner's
  `Group.Read.All` / `GroupMember.Read.All` requirement in `docs/prerequisites.md` is
  **correct and unchanged** — that scanner does resolve group membership via
  `Get-PnPEntraIDGroupMember`.

### 2. `Get-AzAccessToken` example broken on current Az.Accounts — doc accuracy
- **Gap:** Examples used `(Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token`
  and fed the result to the `[string]$AccessToken` parameter. On Az.Accounts 5.x, `.Token`
  is a `SecureString` by default, so this binds the type name (not the token) and auth fails.
- **Fix:** Updated both examples (README and script `.EXAMPLE`) to
  `(Get-AzAccessToken -ResourceTypeName MSGraph -AsSecureString).Token` and convert to plain
  text via `[System.Net.NetworkCredential]` before passing to `-AccessToken`.

### Items reviewed and intentionally left unchanged
- **Risk scoring, batch ID↔index contract, claims-encoding comments** — already corrected in
  prior council reviews (CHANGELOG 1.1.0–1.1.2); verified still accurate.
- **PnP scanner auth, managed-identity-first ordering, certificate paths** — match current
  `Connect-PnPOnline` parameter sets; no change needed.
- **`manifest.yaml`** — not modified (no metadata drift; controls/version accurate).

## Runtime-only caveats (cannot be verified without a live tenant)

1. **`link.scope` population for specific-people links.** The Graph `sharingLink` example for
   specific-people links does not always include `scope: "users"`. If a tenant returns such a
   permission without `scope`, the scanner classifies it as `OtherLink` (via the `default`
   switch branch) rather than `SpecificPeopleLink`; `grantedToIdentitiesV2` is still present in
   the response but is only parsed under the `users` branch. Behavior is non-fatal but should be
   confirmed against real tenant data; consider parsing `grantedToIdentitiesV2` regardless of
   `scope` in a future revision.
2. **Sensitivity-label field shape.** `_SensitivityLabel` may store GUIDs rather than display
   names in some tenants; the config tier map must then use GUIDs. Documented in README/
   troubleshooting; unverifiable statically.
3. **Throttling/Retry-After timing.** The batch retry path honors per-sub-response `Retry-After`
   and falls back to exponential backoff; the actual throttling thresholds are service-imposed
   and only observable under load.
4. **Managed identity SharePoint access (`Sites.Selected`) grants** and transitive group
   expansion depend on tenant configuration and cannot be exercised here.

## Lab-readiness assessment

**Lab-ready (static validation passed).** Both scripts parse cleanly, all external API /
permission / authentication assertions are confirmed against authoritative Microsoft and
PnP.PowerShell sources, documentation is complete (prerequisites, step-by-step, expected
outputs, troubleshooting), and the solution honors the no-runtime-artifact and language-rule
conventions. Two documentation/permission gaps were corrected (least-privilege Graph scope and
the Az.Accounts `SecureString` token example). Remaining caveats are inherently runtime-only and
require a live tenant to exercise; they are documented above and do not block lab validation.

## Second-Pass Command-Existence Re-Verification (2026-06-05)

An independent second-pass audit re-derived every invoked command, cmdlet, CLI verb, REST endpoint and api-version, Dataverse entity set / logical column / option-set, and module against Microsoft Learn, with a sharpened focus on confirming each surface exists and will run in a live lab. Every PnP.PowerShell cmdlet and parameter (Connect-PnPOnline, Get-PnPEntraIDGroupMember -Transitive, Register-PnPEntraIDAppForInteractiveLogin), the Microsoft Graph v1.0 driveItem permissions route, and the Az.Accounts token shape were confirmed against authoritative sources; no corrections required.

## Third-Pass Technical Accuracy Review (2026-06-05)

A third-pass technical-accuracy review (v1.1.3) corrected a finding the earlier passes
missed: the SharePoint login-name `c:0(.s|true` was classified and commented as
"Everyone except external users". That string is the **Everyone** claim (all users),
which can include external/guest users when the tenant enables it
(`Set-SPOTenant -ShowEveryoneClaim $true`) — a distinct, broader principal than
"Everyone except external users" (`c:0-.f|rolemanager|spo-grid-all-users`). The scanner
now classifies `c:0(.s|true` as `EveryoneClaim` and additionally detects the genuine
"Everyone except external users" claim. This supersedes the line above that recorded the
claims-encoding comment as "verified still accurate."

| Claim (in code/docs) | Verified against | Result |
|----------------------|------------------|--------|
| `c:0(.s|true` is the **Everyone** claim (all users; may include external) — not "Everyone except external users" | [Grant the Everyone claim to external users](https://learn.microsoft.com/troubleshoot/microsoft-365/admin/access-management/grant-everyone-claim-to-external-users); [Default SharePoint groups](https://learn.microsoft.com/sharepoint/default-sharepoint-groups#special-sharepoint-groups) | ✅ Corrected (was mislabeled) |
| `GET /sites/{site-id}/permissions` requires `Sites.FullControl.All` | [List permissions on a site](https://learn.microsoft.com/graph/api/site-list-permissions?view=graph-rest-1.0) | ✅ Confirmed (README claim accurate) |

