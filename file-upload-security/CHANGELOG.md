# Changelog

All notable changes to the File Upload Security Configurator will be documented in this file.

## [Unreleased]

### Validated

- **Live tenant validation completed 2026-06-13 against the lab validation tenant (lab evidence).** The three FUS tables (41 columns; `fsi_severity` as a String, `fsi_zone` bound to the canonical `fsi_acv_zone` set) were deployed and verified, and the bot-config-STATE detector (`aISettings.isFileAnalysisEnabled`) was exercised on disposable-bot fixtures: an upload-enabled Enterprise/Zone 1 fixture flagged Critical and persisted (`fsi_zone=100000001`, `fsi_severity="Critical"`), an upload-disabled fixture produced no row, a same-fixture flip discriminated, and an absent nested node resolved to Indeterminate (never a false Compliant), with a real-agent cross-check. The SHA-256 evidence digest recomputed to an integrity match (prefix `E195D5B5…`); all disposable fixtures were torn down (the three FUS tables back to 0, orphaned botcomponents removed, the two real agents untouched) and the deployed schema is retained as the deliverable. Coverage stays **PARTIAL** (bot-config STATE only; runtime upload telemetry and Purview DLP remain out of lab scope). This is lab evidence on disposable fixtures, not proof of behavior in a customer's production tenant. See `LAB-VALIDATION.md` "Live tenant validation outcome (2026-06-13)".

### Changed

- **Zone semantics reconciled to canonical meaning (coordinator decision Option A).** FUS now treats **Zone 1 (Enterprise) as the most-restrictive tier** and **Zone 3 (Personal) as the least-restrictive**, matching the producing `agent-intake` schema and the live `fsi_acv_zone` set. The strictest file-upload policy (disabled, Highest moderation) attaches to Zone 1 / `100000001`; the discretionary policy attaches to Zone 3 / `100000003`. Flipped the naming classifier (`scripts/shared/Get-ZoneClassification.ps1`, `scripts/private/Get-ZoneClassification.ps1` — enterprise→Zone1, personal→Zone3, fail-closed→Zone1), `templates/fileupload-baseline.json` (policy rows + violation-type keys), `scripts/private/Get-ExpectedFileUploadPolicy.ps1` (violation types, branch, regulatory-context), the runbook "weakened drift" Critical escalation (`scripts/Start-FileUploadValidationRunbook.ps1` — now keys on Zone 1), the Teams alert template, and all docs. New `tests/ZoneReconciliation.Tests.ps1` locks "most-restrictive ⇔ Zone 1 ⇔ 100000001". Supersedes the prior integer-by-number-only reconciliation.

### Fixed

- **`fsi_severity` write rejected/mis-rendered against the live `fsi_acv_severity` set.** The violation `fsi_severity` column bound the global `fsi_acv_severity`, which on the live tenant is a monitoring-RESULT set (`Passed/Warning/GracePeriod/Failed/Error`), not a severity rank — so `Warning` (`100000005`) had no live member (write rejected) and the `0–4` writes mis-rendered. `fsi_severity` is now a free String column (mirroring CMM) written with the label text (`Critical/High/Medium/Warning/Info`); dropped the `fsi_acv_severity` bind, the `ConvertTo-SeverityOptionValue` integer conversion (`scripts/private/FUSClient.psm1`), and the divergent `fsi_acv_severity` declaration in `scripts/create_dataverse_schema.py`.
- **`Get-ZoneClassification` dot-source defect (found during the 2026-06-13 live leg).** `scripts/private/Get-ZoneClassification.ps1` dot-sourced the parameterised shared zone script (`scripts/shared/Get-ZoneClassification.ps1`), which executed its mandatory-parameter body at import time and left the wrapper function undefined. It now invokes the shared script via the call operator (`&`) with a naming-convention fallback, so the canonical ELM zone classifier resolves correctly.

### Fixed

- **HIGH (command-existence): `Get-FUSEnvironmentVariable` used a non-existent `$expand` navigation property.** The Dataverse environment-variable lookup expanded `environmentvariablevalues`, which is not a valid navigation property on `environmentvariabledefinition` and fails the OData request ("Could not find a property named 'environmentvariablevalues'"). Replaced with the canonical one-to-many navigation property `environmentvariabledefinition_environmentvariablevalue($select=value)` and updated the downstream property read. `scripts/private/FUSClient.psm1`. Verified against the [Environment Variable Definition table reference](https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/environmentvariabledefinition) (relationship `environmentvariabledefinition_environmentvariablevalue`). (validation2 second-pass)

### Changed

- **Docs (lab-readiness validation):** README "Copilot Studio file input limits" note re-verified against the current [Allow file input from users](https://learn.microsoft.com/microsoft-copilot-studio/image-input-analysis) Microsoft Learn page. Added DOCX to the supported user-upload types and the XLSX/PPTX experimental caveat; replaced the stale per-format limits (4 MB DirectLine cap, 40-page PDF, 180 KB TXT/CSV) with the currently documented limits (15 MB individual file size; 30,000-character text limit without code interpreter, no limit with code interpreter); clarified that knowledge-source uploads are a separate 512 MB feature.
- **Docs:** Added `LAB-VALIDATION.md` capturing static-validation evidence, authoritative Microsoft sources, verified script/API claims, and runtime-only caveats (undocumented `bot.configuration` JSON schema, MSAL.PS deprecation, runbook certificate-only auth).

## [1.1.2] - 2026-05-23

AI Council technical-accuracy review (council-review/file-upload-security-review.md). Verbose-summary completeness, runbook version requirement, and version-header alignment.

### Fixed

- **Major**: Compare-FileUploadCompliance.ps1 verbose severity summary now iterates all six severities (`Critical`, `High`, `Medium`, `Low`, `Warning`, `Info`); previously skipped `Low` and `Info` in the verbose output loop even though the counters tracked all six. `scripts/Compare-FileUploadCompliance.ps1:200`. (council review M1)
- **Minor**: Start-FileUploadValidationRunbook.ps1 `#Requires -Version` raised from `7.0` to `7.4` to match the other entry-point scripts and the `Get-Date -AsUTC` usage on lines 459 and 493 (PowerShell 7.1+ feature). `scripts/Start-FileUploadValidationRunbook.ps1:1`. (council review m1)
- **Minor**: Version strings in `.NOTES` blocks of `Compare-FileUploadCompliance.ps1`, `Get-AgentFileUploadSettings.ps1`, and `private/Get-ExpectedFileUploadPolicy.ps1` synced from stale `1.0.0` to current solution version. (council review m2)

### Changed

- **Chore**: Replaced non-ASCII punctuation (em-dash, en-dash, smart quotes) with ASCII equivalents across all PowerShell scripts under `scripts/` to satisfy the cross-cutting style sweep. No behavior change.

### Deferred (tracked for future)

- **m3** (Boolean type for `fsi_FUS_IncludeSandbox` / `fsi_FUS_IncludeDrafts` env vars): requires changing Dataverse env-var type and re-keying existing rows; documented behavior is correct and the schema doc already calls out the String-based representation.
- **m4** (`fsi_FUS_GracePeriodHours` default 24 vs PowerShell 48): intentional documented precedence; schema.md already explains the runtime override.
- **m5** (Decimal -> JSON env-var workaround): cosmetic comment improvement only; behavior is correct.

## [1.1.1] — 2026-05-17

### Added

- **Downstream attachment validation guide.** New `docs/downstream-validation.md` documents how downstream consumers should validate file attachments after upload, covering file magic-number validation, Microsoft Defender for Cloud integration checks, and sensitivity label inheritance verification with PowerShell and Python code examples.

### Changed

- Bumped target version to 1.1.1 for the Microsoft Learn 2026-Q2 refresh.
- Updated Copilot Studio file-input limits, channel caveats, Dataverse MIME controls, Graph attachment guidance, Defender for Cloud Apps scope, and Purview DLP limitations.
- Added managed-identity-first Python Dataverse authentication with workload identity and local developer credential fallback; client-secret auth is retained only as a legacy development fallback.

## [1.1.0] — 2026-04-17

AI Council technical-accuracy review (Claude Opus 4.7 + Goldeneye). Bug fixes, regulatory-language corrections, and runtime hardening; existing column writes are preserved (non-breaking).

### Fixed

- **Schema:** `create_dataverse_schema.py` now declares the required `fsi_name` primary string attribute inline when creating each table. Without this, Dataverse rejects entity creation with error 0x80048408 — the schema would never deploy successfully on a fresh tenant despite all helper functions writing `fsi_name`.
- **Environment-variable type map:** `create_environment_variables.py` `TYPE_MAP` corrected — `JSON` is option-set value `100000003` (previously incorrectly mapped to `100000002`, which is `Boolean`). Added missing `Boolean`, `Number`, `DataSource`, and `Secret` entries.
- **Severity option-set drift:** `Compare-FileUploadCompliance.ps1` summary counters now include `Info` and `Low` severities (previously only counted `Critical`/`High`/`Medium`/`Warning`, silently dropping any `Info`/`Low` violations from severity rollups). Mirrored in `Test-FileUploadCompliance.ps1`.
- **Severity 'None':** `Get-ExpectedFileUploadPolicy.ps1` initial severity changed from `'None'` to `'Info'` so the option-set conversion succeeds. `ConvertTo-SeverityOptionValue` (FUSClient.psm1) also accepts `'None'` as a legacy alias for `'Info'` to avoid silent `$null` writes.
- **Fail-closed orchestration:** `Get-AgentFileUploadSettings.ps1` now tracks per-environment auth/connectivity skips and throws when ALL targeted environments are skipped — previously the script returned an empty array, causing `Test-FileUploadCompliance.ps1` to record a green PASS evidence row with zero coverage. `Test-FileUploadCompliance.ps1` also throws on empty result sets unless the new `-AllowEmptyResultSet` switch is supplied for explicit opt-in.
- **statecode/statuscode pair:** baseline deactivation `PATCH` (`FUSClient.psm1`) now sends `statecode = 1` AND `statuscode = 2` together — Dataverse rejects partial state transitions silently in some configurations.
- **Az.Accounts compatibility:** `Connect-EnvironmentDataverse.ps1` now tries the Az.Accounts 5.x `-ResourceUri` parameter first and falls back to the deprecated `-ResourceUrl` only when running on Az.Accounts 4.x.

### Changed

- All entry-point scripts (`Test-FileUploadCompliance.ps1`, `Get-AgentFileUploadSettings.ps1`, `Compare-FileUploadCompliance.ps1`, `Export-FileUploadEvidence.ps1`, `Invoke-FileUploadBaselineCapture.ps1`, `Test-EvidenceIntegrity.ps1`) now declare `#Requires -Version 7.4` since they all depend on PowerShell 7.4 features (`ConvertFrom-SecureString -AsPlainText`, `Get-Date -AsUTC`, etc.).
- Regulatory references standardised to full citation form: `FINRA Rule 4511`, `FINRA Regulatory Notice 25-07`, `SEC Rule 17a-3` (was bare `FINRA 4511` / `FINRA 25-07` / `SEC 17a-3`).

### Removed

- **OCC 2011-12 / SR 11-7 misclaim:** removed from README control table, `Get-ExpectedFileUploadPolicy.ps1`, `templates/fileupload-baseline.json`, and `create_environment_variables.py`. OCC 2011-12 is the model-risk-management bulletin (covered by `model-risk-management-automation`); file-upload data-minimisation is covered by FFIEC IT Booklet — Information Security and the Interagency Guidelines (12 CFR 30 App. B).

## [1.0.2] — 2026-04-15

### Fixed

- Critical: Entity set name corrected from fsi_fileuploadvalidationhistorys to fsi_fileuploadvalidationhistories (was malformed plural)

## [1.0.1] — 2026-03-01

### Changed
- Moved `src/adaptive-card-fileupload-alert.json` to `templates/` per solution content policy
- Updated README, `flows/README.md`, and `docs/FLOW_SETUP.md` to reflect new paths

### Removed
- `src/fileupload-validation-flow.json` — Replaced by manual build instructions in `docs/FLOW_SETUP.md`
- `src/dataverse/` scaffolding (empty placeholder directories and READMEs) — Schema deployed via `scripts/create_dataverse_schema.py`
- `src/` directory entirely

## [1.0.0] — 2026-02-10

### Added

- Initial release of File Upload Security Configurator
- `Get-AgentFileUploadSettings.ps1` — Per-agent file upload enumeration across environments
- `Compare-FileUploadCompliance.ps1` — Zone-based compliance comparison with severity classification
- `Test-FileUploadCompliance.ps1` — End-to-end orchestrator with dry-run mode and multi-format output
- `FUSClient.psm1` — Dataverse client module for file upload metadata queries
- Content moderation cross-check for file-upload-enabled agents
- Zone policy model: Zone 1 (Allowed), Zone 2 (Restricted), Zone 3 (Disabled)
- Dataverse schema: fsi_fileuploadbaseline, fsi_fileuploadvalidationhistory, fsi_fileuploadviolation tables
- Power Automate daily validation flow with Teams adaptive card alerts
- Azure Automation runbook wrapper for unattended execution
- SHA-256 integrity-hashed evidence export for SEC 17a-4(f) support
- Baseline capture and drift detection
- Control 1.14 framework integration
- Complete documentation suite (PREREQUISITES, SCHEMA, EVIDENCE_EXPORT, FLOW_SETUP, TROUBLESHOOTING)
