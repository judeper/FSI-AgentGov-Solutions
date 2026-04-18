# Changelog

All notable changes to agent-knowledge-source-scanner will be documented in this file.

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
