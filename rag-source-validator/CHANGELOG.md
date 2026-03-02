# Changelog

All notable changes to the RAG Source Validator.

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
  - Schema drift detection
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
