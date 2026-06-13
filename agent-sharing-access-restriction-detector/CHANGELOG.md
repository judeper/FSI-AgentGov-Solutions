# Changelog

All notable changes to the Agent Sharing Access Restriction Detector are documented here.

## [Unreleased]

### Changed

- `Invoke-SharingComplianceScan.ps1 -ExcludeSandbox` now uses standard switch semantics (default `$false`); callers that want to omit sandbox environments should pass `-ExcludeSandbox`.

### Documentation

- Corrected `docs/prerequisites.md` to point to this solution's own `scripts/` folder for the schema-creation and supporting scripts (previously mislabeled as the companion FSI-AgentGov repository).
- Added the `scripts/` subtree to the README Components listing so the Python and PowerShell automation is discoverable from the directory map.
- Added `LAB-VALIDATION.md` documenting static lab-readiness validation, authoritative Microsoft Learn source verification (Dataverse `bot.accesscontrolpolicy`/`authorizedsecuritygroupids`, Managed Environment sharing limits, 28-day approval wait, Power Apps admin cmdlets), and runtime-only caveats.
- Recorded ASARD's sharing-plane coverage in `LAB-VALIDATION.md`: plane #1 (runtime chat ACL) is validated; the authoring-share (`PrincipalObjectAccess` Editor/Viewer) and M365 Copilot Agent Store planes are documented as known gaps. ASARD is not presented as complete sharing-governance coverage.
- Removed the unverified "sharing limits apply to agents that require authentication" claim from `README.md` and replaced it with an authoritative-scope pointer to Microsoft Learn agent sharing limits.
- Added `docs/approvals-limits.md` capturing the 28-day approval ceiling, the `Create an approval`/`Wait for an approval` adjacency build invariant, and the >4-agent batch/child-flow overflow pattern.
- Added `docs/option-set-integers.md` requiring in-env verification of the custom `100000000`-series option-set integers via `GlobalOptionSetDefinitions`, and flagging the `fsi_acv_zone` `0`-`3` (script) vs `100000000`-`100000003` (in-env, lab-verified) drift for live reconciliation; added an in-situ pointer comment at the hardcoded sites in `Invoke-SharingComplianceScan.ps1`.
- Softened residual FSI vocabulary in `README.md` "Known Limitations" (operational notes now read "avoid"/"verify"/"remove" instead of "prevent"/"ensure"/"eliminate").

## [2.0.2] — 2026-05-23

### Fixed

- **Major**: Regenerated `docs/dataverse-schema.md` so it now includes the three admission gate columns on `fsi_approvedsecuritygrouppolicy` (`fsi_SecurityEnabled`, `fsi_MailEnabled`, `fsi_GroupTypes`). The docs file was stale; the schema script defined the columns but `--output-docs` had not been re-run after they were added. (council review M1)

### Changed

- **Major**: `Export-SharingComplianceEvidence.ps1` no longer depends on the archived MSAL.PS module. Authentication now uses direct OAuth 2.0 REST calls to the `https://login.microsoftonline.com/{tenant}/oauth2/v2.0/{token,devicecode}` endpoints, matching the pattern already established in `Invoke-SharingComplianceScan.ps1`. `-Interactive` now drives a device-code flow (user pastes a one-time code into https://microsoft.com/devicelogin); unattended runs take `-ClientSecret` (SecureString) for client_credentials. Client secrets remain flagged as a legacy dev-only fallback per the managed-identity-first authentication standard. (council review M2)
- **Minor**: Clarified `Test-AgentSharingCompliance.ps1 -DataverseToken` parameter as `[RESERVED — unused in this version]` in the comment-based help, and removed the misleading `-DataverseToken $token` usage from the `.EXAMPLE` block. The parameter was accepted but never forwarded to the scan script; behavior unchanged. (council review m2)
- **Minor**: Clarified `asard_group_admission.py --access-token` argparse help text as `[RESERVED — unused in this version]`. The script validates only locally-loaded JSON today; live Graph API lookup is reserved for a future enhancement. (council review m5)

### Removed

- **Major (BREAKING for callers using cert-based auth)**: `Export-SharingComplianceEvidence.ps1 -CertificateThumbprint` is removed in 2.0.2. The certificate-based service-principal path required the archived MSAL.PS module. Passing this parameter now throws a terminating error explaining the migration. Affected callers should switch to `-ClientSecret` (legacy dev-only) or migrate to a managed-identity-backed token-acquisition wrapper. The parameter declaration is retained only so the error message reaches callers that still pass it; it will be deleted in a future minor.

### Notes

- **m1 (Minor) DEFERRED**: Council recommendation to add a clarifying comment to `scripts/shared/Get-ZoneClassification.ps1` about ELM vs ASARD option set value drift. The shared script is owned by the shared-utilities lane (Wave 5 E6) and is explicitly out of scope for per-solution PRs per the orchestrator refinement; deferred for cross-solution coordination.
- **m4 (Minor) DEFERRED**: Council recommendation to bump `adaptive-card-asard-remediation-approval.json` from schema version 1.4 to 1.5 for parity with the result card. The council confirmed there is no functional issue — the approval card does not use `isVisible` on actions (the 1.5 feature that required the result card bump). Pure-cosmetic version sync is deferred per the Wave 3 minor-finding deferral rubric.

## [2.0.1] — 2026-05-17

### Fixed

- Critical: `Invoke-SharingComplianceScan.ps1` now evaluates Copilot Studio agent sharing from the Dataverse `bot.accesscontrolpolicy` and `bot.authorizedsecuritygroupids` columns instead of the non-current `sharingtype` field and unsupported `Get-AdminPowerAppRoleAssignment -ResourceType/-ResourceId` parameters.
- High: Bot query failures now surface as `SCAN_COVERAGE_GAP` findings instead of being silently skipped and reported as clean scans.
- Medium: Documentation refreshed for 2026-Q2 Microsoft Learn guidance covering Managed Environment agent sharing limits, Editor/Viewer role behavior, the 28-day approval wait caveat, and managed-identity-first authentication language.

## [2.0.0] — 2026-04-30

### BREAKING

- **Sharing-principal enumeration switched** from the Dataverse `botcomponentroleassociations` table to `Get-AdminPowerAppRoleAssignment` (Microsoft.PowerApps.Administration.PowerShell). The previous query returned Dataverse security role GUIDs and could never match the Entra group object IDs stored in `fsi_securitygroupid`, producing false negatives on every Zone 2 / Zone 3 evaluation (the solution's primary control). The replacement requires an `Add-PowerAppsAccount` session — `Invoke-SharingComplianceScan.ps1` now establishes one immediately after acquiring the OAuth token. Service principals **must** now be registered as Power Platform admins (`Add-PowerAppsAccount` will throw if they are not).
- **`Test-AgentSharingCompliance.ps1 -PersistResults` is now documented as a no-op.** Per-violation rows are persisted by `Invoke-SharingComplianceScan` when `-DataverseUrl` is supplied; there is no separate summary persistence. The switch is retained for backward compatibility and will be removed in a future major.

### Fixed

- High: `-ExcludeTrial` is now actually applied. The switch was accepted by `Test-AgentSharingCompliance.ps1` and documented in its `.PARAMETER` block but was never forwarded to the scan script and the scan script had no trial-filter logic. Added the parameter to `Invoke-SharingComplianceScan.ps1`, the `EnvironmentType -eq 'Trial'` filter, and the forwarding line in the wrapper.
- High: Adaptive card `adaptive-card-asard-remediation-result.json` bumped to schema version `1.5` so `isVisible` on `Action.OpenUrl` renders correctly in modern Teams clients (1.4 does not reliably support action visibility).
- Medium: Connector ID `shared_httppremium` (does not exist in the connector registry) corrected to `shared_http` in `create_asard_connection_references.py`. Flows referencing the bad connector ID would have failed to bind.
- Medium: `fsi_ASARD_ApprovalTimeoutDays` environment variable type label corrected from `"Decimal"` to `"Number"` in `create_asard_environment_variables.py`. The Dataverse type code (`100000001`) was already correct (Number); only the label was misleading.
- Medium: `contoso.onmicrosoft.com` examples replaced with `example.onmicrosoft.com` in `Export-SharingComplianceEvidence.ps1`.
- Medium: Adaptive card `_metadata.violationTypeMapping` keys in `adaptive-card-asard-alert.json` and `adaptive-card-asard-remediation-approval.json` updated from the legacy UASD set (`Everyone`, `Public`, `ExcessiveIndividual`, `CrossTenant`) to the keys actually emitted by `asard_zone_rules.py` (`GroupSharing`, `OrgWideSharing`, `PublicSharing`, `UnapprovedGroup`).
- Medium: `docs/prerequisites.md` table now distinguishes logical name (`fsi_agentsharingcompliance` singular) from entity-set name (`fsi_agentsharingcompliances` plural). The single "Logical Name" column conflated the two.
- Medium: Dataverse-auth failure path in `Invoke-SharingComplianceScan.ps1` now sets `$script:DataverseAuthFailed` so callers can detect the silent downgrade to no-persistence.

## [1.0.4] — 2026-04-15

### Fixed

- Critical: Zone filters now use integer option set values instead of string literals in Export and Scan scripts
- Critical: Compliance record primary field changed from fsi_name to fsi_complianceid (matches schema)
- Critical: Added missing fsi_compliancestatus field to compliance record writes
- Policy column fsi_name changed to fsi_policyname (matches schema)
- Policy filter uses fsi_isactive instead of statecode for business-level active check
- Sharing type persists label text instead of raw numeric value

## [1.0.3] — 2026-04-10

### Added
- Dataverse schema script with 2 tables, 3 option sets, and `--output-docs` support
- Environment variables script (4 variables for template URL, BAP API, approval timeout, governance lead)
- Connection references script (Dataverse, Teams, Approvals, HTTP Premium)
- PowerShell governance scripts: Invoke-SharingComplianceScan, Test-AgentSharingCompliance, Get-ExpectedSharingPolicy, Export-SharingComplianceEvidence, Test-EvidenceIntegrity
- Python zone rules engine (asard_zone_rules.py) with zone policy evaluation
- Auto-generated Dataverse schema documentation
- Seven new columns on AgentSharingCompliance table: SharingType, ViolationType, Severity, Description, ScanRunId, SharedGroupIds, RegulatoryContext

### Fixed
- Aligned PS script column references with Dataverse schema (`fsi_groupid` → `fsi_securitygroupid`, `fsi_groupname` → `fsi_securitygroupname`)
- Removed `exit 0` from Invoke-SharingComplianceScan.ps1 and Test-AgentSharingCompliance.ps1 (broke dot-sourcing)
- Fixed snake_case column names in docs and adaptive card templates to match Dataverse logical names
- Fixed ComplianceStatus option set values in docs (was 0–3, corrected to 100000000–100000003)
- Fixed CHANGELOG date ordering (v1.0.2 was incorrectly dated July 2025)
- Added MSAL.PS deprecation notice in Export-SharingComplianceEvidence.ps1

## [1.0.2] — 2026-03-20

### Changed
- Restructured solution to follow standard layout
- Moved adaptive card templates from `src/` to `templates/`
- Removed exported Power Automate flow JSON from `src/` (per content policy)
- Added `docs/` with `flow-configuration.md` and `prerequisites.md`

## [1.0.1] — 2026-03-10

### Fixed
- **CRITICAL**: ApprovalTimeoutDays null guard now uses `coalesce()` in both branches of the ternary, preventing null from producing an invalid ISO 8601 duration (`"PD"`)
- **WARNING**: Unknown zone values now default to Zone 1 (most restrictive — remove all access) instead of Zone 3 (least restrictive) in `Build_Permission_Objects` and `Build_Approval_Card_Data`
- **WARNING**: `Start_Approval` and `Wait_For_Approval` wrapped in `Scope_Approval` with `Handle_Approval_Scope_Failure` error handler that updates Dataverse to Error status on connector failure
- **WARNING**: Exception review queries (`Query_Expiring_Exceptions`, `Query_Expired_Exceptions`) increased `$top` from 100 to 5,000 (Dataverse maximum) to reduce silent data loss risk

### Documentation
- Added N+1 approved groups query pattern to README Known Limitations
- Updated exception query pagination documentation to reflect 5,000 record limit

## [1.0.0] — 2026-02-15

### Added
- Remediation approval workflow (`asard-remediation-approval-workflow.json`) for governance-gated sharing corrections
- Exception review workflow (`asard-exception-review-workflow.json`) for automated expiration handling and renewal notifications
- Violation alert adaptive card (`adaptive-card-asard-alert.json`) for Teams notifications
- Remediation approval adaptive card (`adaptive-card-asard-remediation-approval.json`) for approval requests
- Remediation result adaptive card (`adaptive-card-asard-remediation-result.json`) for outcome notifications
- Exception expiring warning card (`adaptive-card-asard-exception-expiring.json`) for proactive renewal prompts
- Exception expired notification card (`adaptive-card-asard-exception-expired.json`) for expiration alerts
- All 7 artifacts created for zone-based agent sharing governance
