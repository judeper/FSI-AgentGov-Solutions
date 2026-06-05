# Changelog — Cross-Solution Integration

All notable changes to this solution will be documented in this file.

## [Unreleased]

### Changed

- **Operator ergonomics (Wave 6 P4a):** State-changing scripts now support `-WhatIf` and `-Confirm` switches via `SupportsShouldProcess`. Existing callers see no behavior change unless they explicitly pass `-WhatIf`.

### Fixed

- **Second-pass command-existence (P0 column fix):** Evidence registration in `Sync-SolutionAssessments.ps1` wrote the non-existent column `fsi_description` on `fsi_complianceevidence`; the schema defines the memo column as `fsi_evidencedescription` (`compliance-dashboard/scripts/create_cd_dataverse_schema.py:204`). A live Web API `POST`/`PATCH` would have returned `400` (property does not exist). Corrected both evidence writes (`scripts/powershell/Sync-SolutionAssessments.ps1`) and the documented payload in `docs/status-mapping.md`.
- **Wave 6 P4b:** Empty catch blocks now log via `Write-Verbose` instead of silently swallowing errors. Output is unchanged unless caller passes `-Verbose`.

### Documentation

- **Lab-readiness validation (no code changes to scripts):** Static cross-solution validation confirmed every Tier 2 history-table entity set and column referenced by `Sync-SolutionAssessments.ps1` and `Export-UnifiedComplianceEvidence.ps1`, the ACV `fsi_environmentregistry` references in `Register-ProvisionedEnvironment.ps1`, and the Compliance Dashboard option-set values (`fsi_cd_status`/`fsi_cd_zone`/`fsi_cd_evidencetype`, intentionally 1-based) against each sibling solution's `create_*_dataverse_schema.py`. Evidence recorded in `LAB-VALIDATION.md`.
- **`PREREQUISITES.md` authentication section corrected:** Documented the **Dataverse Application User + security role** requirement for managed-identity and service-principal authentication (a valid token alone returns `403` without it), and corrected the service-principal description from the delegated `user_impersonation` scope to the client-credentials `.default` scope. Cited the Power Platform admin docs for application users and custom security roles.
- **Module prerequisites corrected:** Removed the unused `Microsoft.PowerApps.Administration.PowerShell` requirement from `PREREQUISITES.md` and `README.md` (the scripts call the Dataverse Web API directly via `Invoke-RestMethod`) and clarified that `MSAL.PS` is required only for interactive or legacy service-principal authentication.

## [2.0.3] — 2026-05-22 — Council review remediation

### Fixed

- **Minor**: Aligned `Test-UnifiedEvidenceIntegrity.ps1` `.NOTES` block from `Version: 2.0.0` to match the rest of the solution. `scripts/powershell/Test-UnifiedEvidenceIntegrity.ps1:23`. (council review m-01)
- **Minor**: Removed the obsolete `fsi_er_zone` reference from `Register-ProvisionedEnvironment.ps1` `.PARAMETER Zone` help text. `fsi_acv_zone` is the only governance-zone option set used by the ELM-to-ACV registration path. `scripts/powershell/Register-ProvisionedEnvironment.ps1:26`. (council review m-02)

### Changed

- **Major**: Documented the `agent-observability-foundation` dependency declared in `manifest.yaml` in both `PREREQUISITES.md` and the README Prerequisites section so operators do not miss the foundational telemetry dependency at deploy time. (council review M-02)
- **Major**: Fixed the README Documentation table to reference actual lowercase filenames (`docs/schema-contract.md`, `docs/status-mapping.md`, etc.) as relative links instead of the legacy uppercase display names (`SCHEMA_CONTRACT.md`, `STATUS_MAPPING.md`, etc.). The uppercase forms would not resolve on case-sensitive filesystems. `README.md:62-70`. (council review M-03)
- Version strings bumped from 2.0.2 to 2.0.3 across `manifest.yaml`, README, `IntegrationConfig.psd1`/`psm1`, and the `.NOTES` blocks of `Sync-SolutionAssessments.ps1`, `Export-UnifiedComplianceEvidence.ps1`, `Register-ProvisionedEnvironment.ps1`, and `Test-UnifiedEvidenceIntegrity.ps1`, plus the `moduleVersion` field inside the export manifest emitted by `Export-UnifiedComplianceEvidence.ps1`.

### Notes

- **Council finding C-01 (`fsi_summaryjson` removal) investigated and recorded as FALSE POSITIVE.** The column is defined on every history table the export script references: AAM `fsi_accessvalidationhistory` (`agent-access-monitor/scripts/create_dataverse_schema.py:351`, `SchemaName: fsi_SummaryJson`), CMM `fsi_moderationvalidationhistory` (`content-moderation-monitor/scripts/create_dataverse_schema.py:238`), and FUS `fsi_fileuploadvalidationhistory` (`file-upload-security/scripts/create_dataverse_schema.py:157`). The v2.0.2 CHANGELOG entry that claimed this field was removed was inaccurate — the script was always correct. No change to `scripts/powershell/Export-UnifiedComplianceEvidence.ps1` field arrays.
- **Council finding C-02 (`fsi_validationtype` removal) investigated and recorded as FALSE POSITIVE.** The column is defined on both history tables the export script references: ACV `fsi_auditvalidationhistory` (`audit-compliance-manager/scripts/create_dataverse_schema.py:224`, in `HISTORY_TABLE_COLUMNS`) and SSC `fsi_validationhistory` (`session-security-configurator/scripts/create_dataverse_schema.py:282`, in the `fsi_validationhistory` columns array). The v2.0.0 CHANGELOG note that claimed `fsi_validationtype` does not exist on ACV/SSC history tables was inaccurate — the script was always correct. No change to `scripts/powershell/Export-UnifiedComplianceEvidence.ps1` field arrays.
- **Council finding M-01 (CLAUDE.md root table missing 1.18)** is fixed in `CLAUDE.md` outside this CHANGELOG (manifest already declared all seven controls in v2.0.2).
- **Council finding m-04 (`fsi_severity` may not exist on AAM history)** investigated and recorded as FALSE POSITIVE. The column is defined on `fsi_accessvalidationhistory` in AAM's `HISTORY_TABLE_COLUMNS` (`agent-access-monitor/scripts/create_dataverse_schema.py:307`).
- Council findings m-03 (helper-function deduplication) and m-05 (`.ralph-config.json` creation) deferred per the wave deferral rubric — both are standalone reorgs / new-artifact additions, not co-located one-line fixes.

---

## [2.0.2] — 2026-05-05 — Microsoft Learn refresh (Issue #113)

### Fixed

- Corrected ACV history references to use `fsi_timestamp` and removed the nonexistent `fsi_summaryjson` field from unified evidence export.
- Updated evidence export field lists for CMM, FUS, and CAA so `$select` contains only columns present on each validation history table.
- Updated ELM-to-ACV registration to write ACV option-set values for `fsi_zone` and `fsi_environmenttype` while still accepting legacy small integers from flow inputs.
- Updated transient retry handling in sync, export, and registration scripts to honor `Retry-After` and avoid null dereferences on connection errors.

### Changed

- Added managed identity authentication to integration scripts and made MSAL.PS optional for interactive or legacy dev-only service principal authentication.
- Refreshed flow and evidence documentation against 2026-Q2 Microsoft Learn guidance for Dataverse Web API `$select`, service-document entity set names, Power BI/Dataflows, Purview eDiscovery exports, and Graph batching/throttling considerations.
- Reclassified this solution as Tier 2 in the manifest and added Control 1.18 to match the CAA feed mapping.

---

## [2.0.1] — 2026-05-04 — CAA schema follow-up (Issue #36)

### Changed

- Updated CAA history-table column references in `IntegrationConfig.psm1` and `Export-UnifiedComplianceEvidence.ps1` to match the renamed CAA logical names shipped in `conditional-access-automation` v2.0.0 (`fsi_validationtime`, `fsi_runid`, `fsi_overallseverity`, `fsi_totalpolicies`, `fsi_passedcount`, `fsi_warningcount`, `fsi_failedcount`, `fsi_driftcount`).
- `docs/evidence-export.md` and `docs/schema-contract.md` updated to match.

### Notes

- Requires `conditional-access-automation` v2.0.0+. Earlier CAA versions still using underscored logical names are no longer supported by this integration.
- The historical "CAA history columns use underscores" caveat in the v2.0.0 entry below is **no longer accurate** for v2.0.1+; CAA now follows the same single-word convention as every other history table.

---

## [2.0.0] — 2026-04-16 — BREAKING

> Output of an AI Council technical-accuracy review (Opus 4.7 + Goldeneye). Every PowerShell script and integration doc had drifted from the actual Dataverse schemas of the six sibling solutions it integrates. The integration was effectively non-functional out of the box for ACV / SSC / AAM / CMM / FUS / CAA in v1.x.

### BREAKING

- **Severity option set is `100000000`-based (5 values), not `1`-based.** All `IntegrationConfig.psm1` mappings, all flow Compose actions, and all `STATUS_MAPPING.md` / `SCHEMA_CONTRACT.md` / `flow-configuration.md` tables now use the canonical `Passed=100000000`, `Warning=100000001`, `GracePeriod=100000002`, `Failed=100000003`, `Error=100000004` values defined by ACV's `fsi_acv_severity` global option set. Existing flows must be edited.
- **Zone option set is `100000000`-based (4 values, including `Unclassified`), not `1`-based.** `Get-CanonicalZoneValue` no longer remaps to 1/2/3 — values are passed through. Custom callers that assumed canonical 1/2/3 must be updated.
- **AAM and CMM history tables use a singular `EntitySetName`.** REST URLs are now `fsi_accessvalidationhistory` and `fsi_moderationvalidationhistory` (NOT plural). Both schemas declare `EntitySetName` explicitly. Hard-coded `…histories` URLs return 404.
- **Per-finding violation rows are no longer exported.** `Export-UnifiedComplianceEvidence.ps1` writes run-level validation history only. Violation rows often contain agent owner UPNs and similar PII; downstream consumers requiring per-finding detail must read the owning solution's tables directly. The `violations: []` array in the schema is retained for back-compat.
- **`fsi_validationtype` filter removed from all queries.** The column does not exist on ACV / SSC / CAA history tables. The integration now selects the latest run by descending timestamp.
- **CAA history columns use underscores.** The integration now reads `fsi_validation_time`, `fsi_run_id`, `fsi_overall_severity` for CAA only — every other history table uses non-underscored logical names.
- **`IntegrationConfig.psd1` now declares `RequiredModules = @('MSAL.PS')`.** Automation Account-style imports that previously silently failed will now block on a missing dependency.
- **`Connect-DataverseApi` parameter sets:** `[switch]$Interactive` is now `Mandatory` in its parameter set. Previously, omitting it silently fell into the ServicePrincipal set with empty `ClientId` / `ClientSecret`. Callers must pass `-Interactive` explicitly.

### Critical fixes

- **Sovereign-cloud support.** `Connect-DataverseApi` now accepts `-Cloud Public|USGov|USGovHigh|USGovDoD|China|Germany` and routes MSAL authority to the matching login host. `Sync-SolutionAssessments.ps1` and `Register-ProvisionedEnvironment.ps1` expose the same parameter. FedRAMP-High customers (DoD, GCC High) could not authenticate in v1.x.
- **All timestamps are UTC.** Multiple `(Get-Date).ToString('…Z')` calls silently emitted local time with a literal `Z` suffix. New `Get-IsoUtcTimestamp` / `Get-IsoUtcDate` helpers in `IntegrationConfig.psm1` replace every occurrence in `Sync-SolutionAssessments.ps1`, `Export-UnifiedComplianceEvidence.ps1`, and `Register-ProvisionedEnvironment.ps1`.
- **Same-day assessment lookup uses a UTC date window** (`fsi_assessmentdate ge @start and lt @start+1d`) instead of `Microsoft.Dynamics.CRM.On(...)` — the latter expected an ISO timestamp, not a date-only string, and returned 400s. The window is now zone-scoped so the SSC/CAA worst-of-two merge cannot overwrite an assessment for an unrelated zone.
- **Evidence integrity is re-verified at registration time.** `Sync-SolutionAssessments.ps1` now recomputes SHA-256 from disk and fails closed on mismatch with the manifest (and with `.sha256` sidecars). v1.x trusted manifest hashes blindly, defeating tamper-evidence on mutable filesystems.
- **`Test-UnifiedEvidenceIntegrity.ps1`** removed an off-by-one in the failure summary (`$total = $passed + $failed + 1`).

### High-severity fixes

- **`fsi_environmentregistries` is the correct EntitySet** (consonant + y → ies). `fsi_environmentregistrys` returned 404 in v1.x. Fixed in `Register-ProvisionedEnvironment.ps1`, `flow-configuration.md`, and the `EnvironmentRegistry` references in `STATUS_MAPPING.md` and `SCHEMA_CONTRACT.md`.
- **Retry loop honors `Retry-After` header** when present and null-checks `Exception.Response` (which is `$null` on socket errors, raising `'StatusCode' on null reference'`).
- **Non-existent columns dropped from queries.** `fsi_settingname`, `fsi_policyname`, `fsi_expectedvalue`, `fsi_actualvalue`, `fsi_agentname`, `fsi_permissiontype`, `fsi_expectedaccess`, `fsi_actualaccess`, `fsi_moderationpolicy`, `fsi_expectedconfig`, `fsi_actualconfig`, `fsi_scannedon`, `fsi_detectedon` were never on the history tables — they belong on per-finding violation tables, which are no longer exported.
- **`Export-UnifiedComplianceEvidence.ps1`** description and SYNOPSIS rewritten to remove the "ensures audit-ready" overclaim and to call out that this is a *collection* step — WORM/immutable storage downstream is still required for SEC 17a-4(f) tamper-evidence.

### Medium-severity fixes

- **Documentation rewrite:** `SCHEMA_CONTRACT.md`, `STATUS_MAPPING.md`, `EVIDENCE_EXPORT.md`, `flow-configuration.md`, `TROUBLESHOOTING.md` regenerated to match the verified facts above. Per-solution sections call out the singular EntitySet exceptions and CAA's underscored columns.
- `Connect-Dataverse` → `Connect-DataverseApi` references in `TROUBLESHOOTING.md`.
- `fsi_acvzone` / `fsi_acvseverity` references corrected to `fsi_acv_zone` / `fsi_acv_severity` (the actual global option set names).

### Low-severity fixes

- `ELM_INTEGRATION.md`: "ensures the first daily scan includes the new environment" → "supports inclusion".
- `IntegrationConfig.psd1` `FunctionsToExport` now includes `Get-IsoUtcTimestamp` and `Get-IsoUtcDate`.

### Known limitations / not in scope

- ACV does not yet expose a per-finding violation table. The integration treats this as expected (no violation export attempted for ACV). When ACV ships one, this solution will need a minor update to the schema map.
- The integration still cannot read `fsi_environmentregistry` from a tenant where ACV is not deployed; `Register-ProvisionedEnvironment.ps1` will return a clear error in that case rather than silently no-op.
- WORM enforcement is downstream — this solution does not write to immutable storage; that is the customer's responsibility per `EVIDENCE_EXPORT.md`.

### Migration

1. Pull v2.0.0 to your governance environment.
2. Update any custom flows that hard-coded `fsi_severity` 1-5 — the option set values are `100000000`-based.
3. Update any custom flows that hard-coded `fsi_zone` 1-3 — the option set values are `100000000`-based.
4. Update any flow that references `fsi_accessvalidationhistories` / `fsi_moderationvalidationhistories` (plural) — the correct EntitySet for these two tables is the singular form.
5. Remove any `$filter=fsi_validationtype eq 'Orchestrator'` clauses.
6. Add `-Cloud USGovHigh` (or your sovereign cloud) to all `Connect-DataverseApi` callers if you are not on Public.
7. Re-run `Sync-SolutionAssessments.ps1 -DryRun` to confirm the queries return data.

## [1.0.2] — 2026-04-15

### Fixed

- Aligned version strings in all 3 PowerShell scripts to v1.0.1 (were still 1.0.0)

## [1.0.1] — 2026-02-11

### Changed

- **Migrated flow definitions to documentation** — Removed exported Power Automate flow JSON files (`flows/cd-solution-feed-collector.json`, `flows/elm-solution-initializer.json`) and replaced with manual build instructions in `docs/flow-configuration.md`, per the Solution Content Policy
- Updated README Quick Start steps to reference flow build instructions instead of flow deployment

### Removed

- `flows/` directory containing exported Power Automate flow JSON artifacts

## [1.0.0] — 2026-02-10

### Added

- **IntegrationConfig.psm1** — Shared constants module with solution-to-control mappings, status translation, and table configuration
- **Sync-SolutionAssessments.ps1** — PowerShell script to pull Tier 2 validation results into Compliance Dashboard assessments
- **Export-UnifiedComplianceEvidence.ps1** — Master evidence aggregation from all Tier 2 solutions with SHA-256 chain
- **Test-UnifiedEvidenceIntegrity.ps1** — Integrity verification for unified evidence packages
- **CD-SolutionFeedCollector** — Power Automate flow definition for daily automated dashboard feeds
- **ELM-SolutionInitializer** — Power Automate child flow for post-provisioning ACV auto-registration
- **SCHEMA_CONTRACT.md** — Canonical option set contract for cross-solution standardization
- **STATUS_MAPPING.md** — Per-solution status-to-dashboard translation reference
- Documentation suite: README, PREREQUISITES, CONFIGURATION, TROUBLESHOOTING, ELM_INTEGRATION, EVIDENCE_EXPORT, SCORE_CALCULATOR_UPDATE

### Integration Points

- 6 Tier 2 solutions feeding 7 controls into Compliance Dashboard
- ELM provisioning completion cascading to ACV environment registration
- Unified evidence export with per-solution SHA-256 hash chain
