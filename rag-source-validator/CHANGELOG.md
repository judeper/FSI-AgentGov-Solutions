# Changelog

All notable changes to the RAG Source Validator.

---

## [Unreleased]

## [1.3.0] - 2026-05-17

### Added

- **5 new Dataverse columns on `fsi_knowledgesource`.** Additive schema migration adding `fsi_etag` (eTag, String 255), `fsi_ctag` (cTag, String 255), `fsi_deltalink` (Delta Link, Url 2048), `fsi_searchconnectorid` (Search Connector ID, String 100), and `fsi_lineageuri` (Lineage URI, Url 2048). Re-run `create_rsv_dataverse_schema.py` to apply — existing data is unaffected.

### Changed
- Bumped solution metadata to v1.3.0 for the Microsoft Learn 2026-Q2 refresh.
- Added managed identity-first authentication guidance and support for the primary validator and governance reporting scripts, with client-secret authentication retained as a legacy development fallback.
- Expanded planned source-type choices to cover public websites, OneDrive files/folders, Microsoft 365 Copilot connector external items, Azure AI Search indexes, and Copilot Studio uploaded documents.
- Documented Microsoft Graph delta/eTag/lastModifiedDateTime change-detection guidance for SharePoint and OneDrive sources, with SHA-256 hashing retained for evidence integrity.

## [1.2.0] - 2026-04-17

### Council Review — Technical Accuracy Fixes

This release addresses findings from a 2-member AI Council review (Opus 4.7 + Goldeneye) focused on customer-readiness and sovereign-cloud parity with the main validator.

### Fixed
- **High (governance scripts):** `Export-ValidationEvidence.ps1` and `Get-SourceValidationSummary.ps1` hard-coded the OAuth token endpoint to `https://login.microsoftonline.com`, while `Invoke-SourceValidation.ps1` already supported full GCC/GCC-H/DoD/China parameterization. Evidence export against `*.crm.microsoftdynamics.us` / `*.crm.dynamics.cn` would fail with an opaque MSAL error. Added an `-AuthBaseUrl` parameter (`ValidateSet` of the three login endpoints) to both scripts; the token URL is now derived from it.
- **Medium (Invoke-SourceValidation.ps1, `New-SourceChange`):** Same change-type detected on two sources within the same second produced identical `fsi_changename` values — auditor traceability suffered. Now includes the source-name slug (sanitized + truncated) and millisecond precision, e.g. `1-knowledge-policies-pdf-20260417142712345`.
- **Low (Invoke-SourceValidation.ps1):** Added `fsi_description` to the `Get-KnowledgeSources` `$select` projection so human-readable context is available to logs and downstream evidence consumers.
- **Low (regulatory citations):** Normalized to canonical forms across `README.md` and `Invoke-SourceValidation.ps1` — `SEC Rule 17a-4`, `FINRA Rule 4511(a)`, `SOX Section 404`, `GLBA Section 501(b)`.

### Notes (not changed in this release)
- **Option-set value range (consistency):** This solution's option sets define values 1-N, while several other catalog solutions use the 100000000+ Microsoft default custom-publisher range. Both forms deploy successfully via the Web API (explicit `Value` is honored regardless of publisher prefix range), but the inconsistency is tracked for a future major release that would require coordinated updates across the schema script, all hard-coded integers in PowerShell scripts, and `docs/dataverse-schema.md`.
- **Trust-on-first-use baseline classification:** Already differentiated via `fsi_validationtype = 4` (Baseline Capture) and a `BASELINE CAPTURED` log entry. Auditors filtering by validationtype can isolate trust-on-first-use events.

---

## [1.1.1] - 2026-04-15

### Fixed

- Added required primary name fields to Dataverse record writes

---

## [1.1.0] - 2026-04-10

### Added
- Dataverse schema deployment script with 3 tables, 6 option sets, 2 relationships, and `--output-docs`
- Environment variables script (7 variables for Dataverse URL, Graph endpoints, freshness, notifications)
- Connection references script (Dataverse, SharePoint, Teams)
- PowerShell governance scripts: Export-ValidationEvidence (SHA-256), Test-EvidenceIntegrity, Get-SourceValidationSummary
- Auto-generated Dataverse schema documentation from --output-docs
- Python requirements.txt

---

## [1.0.1] - 2026-03-15

### Fixed

- **Binary content hashing fix.** `Get-SharePointContent` now reads raw bytes via `RawContentStream` instead of `$response.Content`, which on PS 7.0–7.3 returned a charset-decoded string for all content types. This ensures SHA-256 hashes for binary files (PDF, DOCX, XLSX) are computed from the original byte stream. Existing baselines for binary sources must be re-captured after this upgrade.
- **Freshness calculation timezone fix.** `[datetime]` parsing of Dataverse UTC timestamps now calls `.ToUniversalTime()` before subtraction to avoid timezone offset errors in freshness threshold comparisons.
- **Source status reflects validation results.** The script now updates `fsi_knowledgesource.fsi_status` after each validation (Active, Validation Failed, or Stale) so the source registry reflects current validation state without querying the separate results table.
- **Non-zero exit code on validation failures.** The script now exits with code 1 when any sources fail, have hash changes, or are stale — enabling CI/CD pipelines to detect validation failures (SEC 17a-4, FINRA 4511).
- **Freshness check for unsupported source types.** Sources with `fsi_freshnessthreshold` and `fsi_lastmodified` metadata now receive staleness checks even when content retrieval is not yet implemented (Dataverse, unsupported types).
- **German sovereign cloud URI removed from SSRF allowlist.** The deprecated `*.sharepoint.de` domain is no longer accepted, since no corresponding Graph or auth endpoints were configured.

---

## [1.0.0] - 2026-02-15

### Added

- Initial release of RAG Source Validator
- **Dataverse Schema:**
  - `fsi_knowledgesource` - Source registry
  - `fsi_validationresult` - Validation history
  - `fsi_sourcechange` - Change tracking
- **Security Roles:**
  - RSV Viewer - Read-only access
  - RSV Validator - Validation and change review
  - RSV Admin - Full access
- **PowerShell Scripts:**
  - `Invoke-SourceValidation.ps1` - Run validation
- **Supported Source Types:**
  - SharePoint Document Libraries (full validation)
  - SharePoint Lists, Pages, Dataverse Tables, Azure Blob Storage, External APIs, Database Queries (registered in schema; validation not yet implemented)
- **Validation Types:**
  - SHA-256 hash validation
  - Schema drift detection (defined in schema; not yet implemented in validation script)
  - Freshness monitoring
- **Documentation:**
  - Prerequisites and licensing
  - Dataverse schema definitions

### Regulatory Alignment

- SEC 17a-4 - Record integrity
- FINRA 4511 - Books and records accuracy
- SOX 404 - Data integrity controls

---

*RAG Source Validator - FSI Agent Governance Framework*
