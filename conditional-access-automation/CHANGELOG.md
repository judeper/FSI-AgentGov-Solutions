# Changelog

All notable changes to the Conditional Access Automation solution are documented here.

## [2.0.0] - 2026-05-04 — BREAKING — Schema convention alignment (Issue #36)

> The CAA Dataverse schema has been re-normalized to follow the team naming convention (single-word PascalCase SchemaNames, lowercase logical names with no underscores between words). Every existing CAA deployment must drop and recreate its three tables before upgrading to this version. See migration steps below.

### BREAKING

- **All CAA Dataverse columns renamed.** SchemaNames previously declared as `fsi_<Word>_<Word>` (e.g. `fsi_Policy_Id`, `fsi_Validation_Time`, `fsi_Is_Active`) are now single-word PascalCase (`fsi_PolicyId`, `fsi_ValidationTime`, `fsi_IsActive`). Microsoft Dataverse generates the LogicalName by lowercasing the SchemaName _and preserving any underscores it contains_ — the prior schema therefore deployed with logical names like `fsi_policy_id`, in violation of the convention documented in `CLAUDE.md` / `AGENTS.md`. Customers running v1.x against a real Dataverse environment must migrate (steps below). Read-only consumers and OData query callers will see a 400/404 against the old logical names after upgrade.
- **`fsi_capolicybaseline`, `fsi_capolicyvalidationhistory`, `fsi_capolicyviolation`** keep their entity logical names (entity table SchemaNames had no internal underscores, so they were already correct). Only column names changed.

### Migration

To upgrade an existing deployment from v1.2.x to v2.0.0:

1. **Export historical data** from the three CAA tables if you need to retain it. Power Automate or Dataverse Web API can dump rows to JSON / blob storage prior to schema rebuild.
2. **Drop the three CAA tables** (or the affected columns individually) via Dataverse admin UI / Web API.
3. **Re-run** `python scripts/create_caa_dataverse_schema.py --tenant-id ... --environment-url ...` from this version of the repo. The script will recreate the columns with the new SchemaNames.
4. **Optional:** replay exported historical data against the new column names. Field-level mapping is mechanical: `fsi_is_active` → `fsi_isactive`, `fsi_validation_time` → `fsi_validationtime`, `fsi_tenant_id` → `fsi_tenantid`, etc. The full mapping is in the v2.0.0 PR description and in the auto-generated `docs/dataverse-schema.md`.
5. **Re-deploy** the three CAA flows / scripts that POST/PATCH against these tables — they reference the new column names automatically once you pull this version of the repo.

### Changed

- `scripts/create_caa_dataverse_schema.py` — every column SchemaName updated to single-word PascalCase. PrimaryNameAttribute references on `fsi_CAPolicyBaseline` and `fsi_CAPolicyViolation` are now `fsi_policydisplayname`; on `fsi_CAPolicyValidationHistory` it is `fsi_runid`.
- `scripts/private/CAAClient.psm1` — every OData `$filter` / `$orderby` / `$select` and every JSON request body field renamed to the new logical names.
- `scripts/private/Get-CAAValidationResults.ps1` — same.
- `scripts/Export-CAAComplianceEvidence.ps1` — same.
- `docs/dataverse-schema.md` — auto-regenerated from the updated schema script.
- `docs/schema.md` — manual schema reference doc updated to match.
- `docs/compliance-monitoring.md` — example queries updated.

### Notes

- The `.ralph-config.json` fact previously asserting that underscored SchemaNames were "correct and intentional" has been corrected; the underscored layout was actually a convention violation that the OData lint script ([`scripts/lint-odata-columns.py`](../scripts/lint-odata-columns.py)) was designed to catch.
- This change closes [Issue #36](https://github.com/judeper/FSI-AgentGov-Solutions/issues/36) and unblocks the soft-gate on `.github/workflows/odata-lint.yml`, which now runs in `--strict` mode.
- `cross-solution-integration` v2.0.1 ships in lockstep to update its CAA-history reader to the new column names.

---

## [1.2.2] - 2026-04-22

### Fixed

- **Critical:** `Get-ZoneClassification.ps1` ELM lookup now queries the correct
  ELM source-of-truth schema (`fsi_environmentrequests` table, `fsi_environmentid`
  filter column, `fsi_zone` picklist column). Previous lookup pointed at
  `fsi_environments` / `fsi_environment_guid` / `fsi_zone_classification` —
  those columns do not exist in ELM, so every lookup silently failed and
  callers fell back to the naming-convention zone classifier.
- `Connect-CAAGraphSession`: added Certificate and ManagedIdentity parameter
  sets so unattended Azure Automation runbooks no longer require interactive
  browser auth.
- `Get-CAAPolicyBaseline`: removed `SupportsShouldProcess` wrap. The function
  is read-only; `-WhatIf` was returning `$null` and breaking
  `Test-PolicyCompliance` and `Watch-PolicyDrift` callers that depend on the
  baseline output.
- `Test-PolicyCompliance`: drift counter math now credits clean policies as
  passed (was counting only drift records). The current side of the
  comparison is now built through `Get-CAAPolicyBaseline` so Zone-derived
  severity escalation works.
- `Compare-CAAPolicyBaseline`: the "removed risk levels" branch now elevates
  severity to 4 (was identical to the no-op arm and never escalated weakened
  policies).
- `Get-CAAValidationResults`: OData `$filter` datetime literals are now
  URL-encoded; previously the `:` and `Z` characters in the ISO-8601
  timestamps caused intermittent 400 BadRequest responses from Dataverse.
- `Export-CAAComplianceEvidence`: requires a valid Entra tenant GUID (no more
  silent fallback to extracting the org subdomain, which never resolved).
  Zone breakdown is now keyed via the picklist
  `…@OData.Community.Display.V1.FormattedValue` annotation, so the report
  shows `Zone1`/`Zone2`/`Zone3` rather than `100000001`+ integers.
- Schema script: `GlobalOptionSet` payloads now include `@odata.type`
  discriminators on the `OptionSetMetadata` root and each `OptionMetadata`
  entry so Dataverse accepts the metadata POST. UTC audit datetime columns
  flipped from `UserLocal` to `TimeZoneIndependent`.
- `Start-CAAValidationRunbook`: env-var lookups now use the actual
  `fsi_CAA_*` SchemaName values created by
  `create_caa_environment_variables.py` (was using bare names like
  `SeverityThreshold`/`IncludeReportOnly` which never resolved).
- `Register-ServicePrincipal`: new certificate parameter set; client-secret
  expiry is now a parameter (default 90 days) instead of a hard-coded year.
- `Watch-PolicyDrift` / `Test-EvidenceIntegrity`: dot-sourced invocation no
  longer terminates the calling runspace. `exit` is now used only for direct
  CLI/CI invocation; dot-sourced callers receive a return value.
- `requirements.txt`: pinned upper bounds on `msal` and `requests`.

### Changed

- `README.md` zone policy table rewritten to match the actual templates
  (Zone 2 and the three Zone 3 templates ship without `signInRiskLevels`;
  M365 Copilot template ships with `low,medium,high`). Added Entra ID P2
  licensing caveat for risk-based controls.
- New optional template `templates/CA-RiskBased-Zone3-Block.json` provides a
  risk-based block control (sign-in risk low+ / user risk medium+) for
  tenants that have Entra ID P2 and want stricter Zone-3 enforcement.
- `docs/SCHEMA.md` option-set values corrected to the Dataverse-issued
  100000000+ range (were 0/1/2/3 placeholders that conflicted with the
  picklist values written by the schema script).
- `docs/compliance-monitoring.md`, `docs/EVIDENCE_EXPORT.md`,
  `docs/deployment-guide.md`, `docs/troubleshooting.md`,
  `docs/policy-templates.md` reconciled with the actual scripts: single
  combined evidence file (no `manifest.json`/`CAPolicies-*.json`/
  `SignInLogs-*.json` artifacts), `Export-PolicyBaseline -OutputPath` is a
  file path (no `-Force` switch), `What-If` Graph endpoint flagged as a
  beta preview, broader Graph scopes documented for deployment validation,
  `Connect-AzAccount` step added before evidence export.
- `docs/prerequisites.md` lists canonical first-party AppIds for Copilot
  Studio (`38e55b99-bd9c-4dff-b510-8d8ee0bff7d6`) and Power Platform Admin.
- `config.sample.json`: `policyPrefix` default changed from `CA` to `CA-FSI`
  to match the prefix every script and template assumes.
- Stripped legacy "(Azure AD)" parenthetical references from PowerShell
  help blocks; "Global Administrator" rephrased to
  "Microsoft Entra Global Admin" in `Register-ServicePrincipal`.
- Module manifest: `ModuleVersion` bumped to 1.2.2; `ReleaseNotes` updated.

## [1.2.1] - 2026-04-15

### Fixed

- Critical: Export-CAAComplianceEvidence now reads correct token variable ($script:CAAAccessToken, was $script:AccessToken)
- Updated EVIDENCE_EXPORT.md version references from 1.1.0 to 1.2.0

## [1.2.0] - 2026-04-02

### Added
- Dataverse schema deployment script with 3 tables, 2 option sets, and `--output-docs` support
- Environment variables script (16 variables for scan config, notifications, Azure infra)
- Connection references script (Dataverse, Office 365, Teams)
- Python requirements.txt

### Changed
- Implemented all 8 CAAClient.psm1 Dataverse functions (previously stubs)
- Implemented Start-CAAValidationRunbook.ps1 (previously NotImplemented placeholder)
  - Full Azure Automation orchestration: auth, compliance checks, drift detection, Dataverse persistence
  - Structured JSON output for Power Automate integration

## [1.1.2] - 2026-07-15

### Changed
- Moved adaptive card template from `src/` to `templates/` (repository content policy alignment)
- Removed `src/caa-daily-compliance-flow.json` and `src/caa-provisioning-hook-flow.json` flow exports (see `docs/` for manual build instructions)
- Removed `src/` directory — solutions provide documentation and scripts, not Power Platform runtime artifacts

## [1.1.1] - 2026-03-13

### Fixed
- Updated `Get-AzAccessToken` fallback in Export-CAAComplianceEvidence.ps1 to use `-AsSecureString` pattern (Az module 12+ compatibility)
- Added Common zone (M365Copilot, BlockLegacyAuth) to coverage tracking in Test-PolicyCompliance.ps1
- Fixed Watch-PolicyDrift.ps1 `-BaselinePath` examples across README and docs to show file path instead of directory
- Updated GLBA regulatory citation to reference FTC Safeguards Rule (16 CFR Part 314)

## [1.1.0] - 2026-02-10

### Added
- CAAClient PowerShell module with 8 Dataverse functions (Connect, Read, Write)
- Azure Automation runbook (Start-CAAValidationRunbook.ps1) for unattended daily execution
- Power Automate daily compliance scan flow (caa-daily-compliance-flow.json)
- ELM provisioning hook flow (caa-provisioning-hook-flow.json)
- Teams adaptive card alert template (adaptive-card-caa-alert.json)
- Dataverse schema: 3 tables (Baseline, ValidationHistory, Violation)
- 7 environment variables with fsi_CAA_* prefix
- 3 connection references with fsi_cr_* naming (Graph connector planned)
- Multi-dimensional drift detection (state, conditions, grants, sessions, additions/removals)
- SHA-256 evidence export (Export-CAAComplianceEvidence.ps1)
- Evidence integrity verification (Test-EvidenceIntegrity.ps1)
- Policy baseline export (Export-PolicyBaseline.ps1)
- Policy drift monitoring (Watch-PolicyDrift.ps1)
- Zone lookup integration with ELM Dataverse
- Dry-run mode for all deployment operations
- PREREQUISITES.md, SCHEMA.md, EVIDENCE_EXPORT.md documentation

### Changed
- Deploy-CAPolicies.ps1 modernized with module structure and WhatIf support
- Test-PolicyCompliance.ps1 extended with Dataverse persistence and drift analysis
- Register-ServicePrincipal.ps1 modernized with Key Vault integration
- Module manifest updated with Tier 2 function exports

## [1.0.0] - 2026-02-15

### Added

- Initial release
- 9 Conditional Access policy templates for AI workloads
- PowerShell deployment scripts with Graph API integration
- Compliance verification and gap analysis
- Policy drift detection with Teams alerting
- Evidence export with SHA-256 integrity hashing
- ELM integration for automated policy deployment
- Documentation suite (prerequisites, templates, deployment, monitoring, troubleshooting)

### Policy Templates

| Template | Target Application | Zone |
|----------|-------------------|------|
| CA-CopilotStudio-Zone1 | Copilot Studio | Zone 1 |
| CA-AgentBuilder-Zone1 | Agent Builder | Zone 1 |
| CA-CopilotStudio-Zone2 | Copilot Studio | Zone 2 |
| CA-CopilotStudio-Zone3 | Copilot Studio | Zone 3 |
| CA-AgentBuilder-Zone2 | Agent Builder | Zone 2 |
| CA-AgentBuilder-Zone3 | Agent Builder | Zone 3 |
| CA-M365Copilot-AllZones | M365 Copilot | All |
| CA-BlockLegacyAuth-AI | All AI apps | All |
| CA-RequireCompliantDevice-Zone3 | Zone 3 apps | Zone 3 |

### Scripts

- `Register-ServicePrincipal.ps1` - Service principal setup
- `Deploy-CAPolicies.ps1` - Template deployment
- `Test-PolicyCompliance.ps1` - Coverage verification
- `Watch-PolicyDrift.ps1` - Drift detection
- `Export-CAAComplianceEvidence.ps1` - Compliance evidence

### Security Alignment

- Zero Trust architecture (verify explicitly)
- NIST 800-53 AC-2, IA-2 controls
- SOX 404 IT general controls
- GLBA 501(b) safeguards rule

### Known Limitations

- Requires Entra ID P1 minimum (P2 for risk-based policies)
- Break-glass accounts must be manually excluded
- Report-only mode recommended before enabling
