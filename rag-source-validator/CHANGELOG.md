# Changelog

All notable changes to the RAG Source Validator.

---

## [1.1.0] - April 2026

### Added
- Dataverse schema deployment script with 3 tables, 6 option sets, 2 relationships, and `--output-docs`
- Environment variables script (7 variables for Dataverse URL, Graph endpoints, freshness, notifications)
- Connection references script (Dataverse, SharePoint, Teams)
- PowerShell governance scripts: Export-ValidationEvidence (SHA-256), Test-EvidenceIntegrity, Get-SourceValidationSummary
- Auto-generated Dataverse schema documentation from --output-docs
- Python requirements.txt

---

## [1.0.1] - March 2026

### Fixed

- **Binary content hashing fix.** `Get-SharePointContent` now reads raw bytes via `RawContentStream` instead of `$response.Content`, which on PS 7.0–7.3 returned a charset-decoded string for all content types. This ensures SHA-256 hashes for binary files (PDF, DOCX, XLSX) are computed from the original byte stream. Existing baselines for binary sources must be re-captured after this upgrade.
- **Freshness calculation timezone fix.** `[datetime]` parsing of Dataverse UTC timestamps now calls `.ToUniversalTime()` before subtraction to avoid timezone offset errors in freshness threshold comparisons.
- **Source status reflects validation results.** The script now updates `fsi_knowledgesource.fsi_status` after each validation (Active, Validation Failed, or Stale) so the source registry reflects current validation state without querying the separate results table.
- **Non-zero exit code on validation failures.** The script now exits with code 1 when any sources fail, have hash changes, or are stale — enabling CI/CD pipelines to detect validation failures (SEC 17a-4, FINRA 4511).
- **Freshness check for unsupported source types.** Sources with `fsi_freshnessthreshold` and `fsi_lastmodified` metadata now receive staleness checks even when content retrieval is not yet implemented (Dataverse, unsupported types).
- **German sovereign cloud URI removed from SSRF allowlist.** The deprecated `*.sharepoint.de` domain is no longer accepted, since no corresponding Graph or auth endpoints were configured.

---

## [1.0.0] - February 2026

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
