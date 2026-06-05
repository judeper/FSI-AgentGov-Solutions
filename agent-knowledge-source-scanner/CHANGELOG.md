# Changelog

All notable changes to agent-knowledge-source-scanner will be documented in this file.

## [Unreleased]

## [1.1.3] - 2026-06-05

### Fixed

- **SharePoint "Everyone" claim mislabeled.** `Get-KnowledgeSourceItemPermissions.ps1` matched the login name `c:0(.s|true` but classified it as `EveryoneExceptExternal` / "Everyone except external users". `c:0(.s|true` is the **Everyone** claim (all users), which can include external/guest users when the tenant enables it (`Set-SPOTenant -ShowEveryoneClaim $true`) — a distinct, broader principal than "Everyone except external users". The claim is now classified as `EveryoneClaim` with an accurate label, and detection for the genuine "Everyone except external users" claim (`c:0-.f|rolemanager|spo-grid-all-users`) was added so that principal is no longer silently treated as a direct permission. Both claim types remain in the out-of-scope set for scoring. Verified against [Grant the Everyone claim to external users](https://learn.microsoft.com/troubleshoot/microsoft-365/admin/access-management/grant-everyone-claim-to-external-users) and [Default SharePoint groups](https://learn.microsoft.com/sharepoint/default-sharepoint-groups#special-sharepoint-groups). `scripts/Get-KnowledgeSourceItemPermissions.ps1:599-615`. (technical accuracy review vs Microsoft Learn)
- **Wave 6 P4b:** Empty catch blocks now log via `Write-Verbose` instead of silently swallowing errors. Output is unchanged unless caller passes `-Verbose`.
- **Least-privilege Graph permissions corrected.** The Graph v1.0 scanner (`Invoke-GraphPermissionScan.ps1`) documentation listed `Group.Read.All` as required, but the [list-permissions endpoint](https://learn.microsoft.com/graph/api/driveitem-list-permissions?view=graph-rest-1.0#permissions) requires only `Files.Read.All` (application) / `Files.Read` (delegated), with `Sites.Read.All` as a higher-privileged alternative. Group-based grants are returned inline in the `grantedToV2`/`grantedToIdentitiesV2` facets, so no group-membership call (and no `Group.Read.All`) is made. Corrected README "Microsoft Graph Permissions" table and the script `.NOTES`. (lab-readiness validation)
- **`Get-AzAccessToken` example updated for Az.Accounts 5.x.** `.Token` is now a `SecureString` by default, so the previous `(Get-AzAccessToken -ResourceUrl ...).Token` example no longer binds to the `[string]$AccessToken` parameter. Examples now use `-ResourceTypeName MSGraph -AsSecureString` and convert to plain text. (lab-readiness validation)

### Added

- **`LAB-VALIDATION.md`** — static (no-tenant) lab-readiness validation report: authoritative Microsoft source verification of Graph endpoints/permissions/batching, PnP.PowerShell 3.x authentication, gaps found and fixed, and runtime-only caveats. (lab-readiness validation)

## [1.1.2] - 2026-05-23

### Fixed

- **Major**: Align `Invoke-GraphPermissionScan.ps1` `.NOTES` version banner with the solution version (was `1.2.0`, now matches the solution). `scripts/Invoke-GraphPermissionScan.ps1:47`. (council review MAJ-01)

### Changed

- **Minor**: Document the batch-request ID-to-`ItemIds`-index contract in the Graph scanner so future edits to either side update both. `scripts/Invoke-GraphPermissionScan.ps1:305-317`. (council review MIN-01)
- **Minor**: Comment the literal `c:0(.s|true` SharePoint claims encoding for "Everyone except external users" so it is not mistaken for a regex or typo. `scripts/Get-KnowledgeSourceItemPermissions.ps1:599-603`. (council review MIN-04)
- **Minor**: Note in `docs/troubleshooting.md` that `Register-PnPManagementShellAccess` applies only to PnP 2.x releases prior to the September 2024 multi-tenant PnP app retirement; later PnP 2.x point releases require a tenant-specific app registration. (council review MIN-07)
- **Minor**: Catalog row in root `CLAUDE.md` Solutions table refreshed (was `v1.1.0`, now `v1.1.2`). (council review MIN-06)

### Notes

- Council review MIN-02 (port `Get-ItemRiskScore` to the Graph scanner) and MIN-03 (add `-OutputPath` CSV export to the Graph scanner) are DEFERRED: both are net-new feature work rather than fixes and warrant their own minor bump with paired test coverage. Tracked for a future v1.2.0.
- Council review MIN-05 (`$IncludeCompliant` accessed via PowerShell dynamic scoping inside `Get-ItemPermissionDetails`) is DEFERRED: council classified this as a style preference, "not a bug"; refactoring to an explicit parameter would touch the function signature and call sites without changing behavior.

## [1.1.1] - 2026-05-17

### Added

- **Graph v1.0 permission scan path.** New `Invoke-GraphPermissionScan.ps1` script uses Microsoft Graph v1.0 `/drives/{driveId}/items/{itemId}/permissions` endpoint for permission scanning. Resolves `grantedToIdentitiesV2` for specific-people links, addressing the `FlexibleLink` limitation in the PnP-based scanner. Required Graph permissions: `Sites.Read.All`, `Files.Read.All`, `Group.Read.All`.
- **JSON batching with ≤20 request cap.** Graph scanner implements JSON batching per [Microsoft Graph batching documentation](https://learn.microsoft.com/graph/json-batching) with a hard cap of 20 requests per batch (Graph's documented limit). Throttled sub-requests (429/503) are retried individually using per-response `Retry-After` headers, with exponential backoff as fallback when the header is absent.
- Documented required Microsoft Graph permissions in README.

### Changed

- Bumped solution metadata to v1.1.1 for the Microsoft Learn 2026-Q2 refresh.
- Added managed identity and certificate authentication modes while keeping interactive authentication for admin workstation scans.
- Updated Entra group expansion to use `Get-PnPEntraIDGroupMember -Transitive` when PnP.PowerShell 3.x is available, with PnP 2.x legacy fallback.
- Refreshed documentation for Copilot Studio SharePoint knowledge source patterns, Microsoft Graph permission shapes, throttling guidance, and Microsoft Purview sensitivity label caveats.

## [1.1.0] - 2026-04-17

### Breaking

- **Risk scoring rebalanced.** `Get-ItemRiskScore` no longer escalates HIGH-tier sensitivity labels to CRITICAL — only the CRITICAL tier (Highly Confidential, Restricted) escalates. HIGH-tier labels exposed out-of-scope are now reported as HIGH (previously CRITICAL). Saved findings dashboards that count CRITICAL rows will see different numbers.
- **OrganizationLink scoring tightened.** Org-wide sharing links are MEDIUM only when the link grants write-equivalent permission (Edit / Contribute / Full Control / Design / Manage Hierarchy). Read-only org-wide links are now LOW (previously MEDIUM).
- **`#Requires -Version` raised from 7.0 to 7.2.** PowerShell 7.0/7.1 are EOL and unsupported by current PnP.PowerShell 2.x releases. Existing 7.0/7.1 deployments will fail at parse time.
- **CSV artifact contract changed.** A header-only CSV is now always written (previously the file was omitted on no-findings runs). Downstream automation that branched on file existence will see the file every run.

### Fixed

- **CRITICAL — agent user scope resolution restored.** `Get-AgentUserScope` was called before any `Connect-PnPOnline`, so `Get-PnPEntraIDGroupMember` failed silently and the scope was always empty (disabling out-of-scope detection entirely when `-AgentUserGroupId` was used). The script now establishes a bootstrap PnP connection before resolving group membership.
- **Group-based oversharing now detected.** `DirectPermission` outside-scope evaluation previously only looked at `User` principals; SharePoint groups and Entra security groups assigned directly to items were always treated as in-scope (the most common SharePoint oversharing pattern). The script now expands `SharePointGroup` (via `Get-PnPGroupMember`) and `SecurityGroup`/`FederatedUser` (via `Get-PnPEntraIDGroupMember` with `Get-PnPAzureADGroupMember` PnP-2.x fallback) and compares each member against the agent user scope. Nested groups remain unresolved (documented limitation).
- **`FlexibleLink` no longer silently dropped.** Previously fell through to `$null` risk score and was excluded from reports unless `-IncludeCompliant` was set. Now treated as out-of-scope (LOW) so the per-recipient grant is at least surfaced for review.
- Comment-based help now documents `.PARAMETER ClientId` (previously missing despite being required for PnP 3.x).
- README "Risk Scoring" matrix updated to match implementation (CRITICAL tier only, write-vs-read OrganizationLink, FlexibleLink low).
- Examples in README, prerequisites, and script switched from `contoso.*` to `example.*` (RFC 2606).

## [1.0.3] - 2026-04-15

### Fixed

- GUID validation for AgentUserGroupId now case-insensitive (accepts uppercase hex)
- Added per-item error handling for HasUniqueRoleAssignments property load (one bad item no longer fails entire library scan)
- Aligned script version banner with solution version
- Updated template metadata version

## [1.0.2] - 2026-04-10

### Added
- `-ClientId` parameter for PnP.PowerShell 3.x tenant-specific app registration support
- Runtime detection of PnP.PowerShell 3.x with clear error when `-ClientId` is missing
- PnP.PowerShell 3.x prerequisites section in docs/prerequisites.md
- `Register-PnPEntraIDApp` setup instructions for tenant-specific app registration

### Changed
- `Get-PnPEntraIDGroupMember` used as primary cmdlet with `Get-PnPAzureADGroupMember` fallback for PnP 2.x backward compatibility
- `Connect-PnPOnline` now uses splatting to conditionally pass `-ClientId`
- Updated quick start examples to show both PnP 2.x and 3.x usage
- Updated troubleshooting guidance for PnP 3.x cmdlet renames and authentication changes

## [1.0.1] - 2026-04-10

### Added
- Documentation suite: docs/prerequisites.md, docs/troubleshooting.md

## [1.0.0] - 2026-03-17

### Added

- `Get-KnowledgeSourceItemPermissions.ps1` — item-level permission scanner for agent knowledge source SharePoint libraries
- Risk scoring tailored to agent knowledge source context (CRITICAL, HIGH, MEDIUM, LOW)
- Sensitivity label cross-reference with configurable tier mapping
- Agent user scope comparison (security group or UPN list)
- CSV and JSON input support for multi-library scanning
- `item-scope-config.sample.json` configuration template
- Comprehensive README with architecture, prerequisites, and quick start
