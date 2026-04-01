# Changelog

All notable changes to MIME Type Restrictions for File Uploads are documented here.

## [1.0.2] — April 2026

### Changed
- Restructured solution to follow standard layout
- Moved documentation from root and src/ to docs/
- Moved KQL queries to scripts/
- Moved JSON templates to templates/
- Retained C# plugin source code in src/

## [1.0.1] — February 2026

### Fixed
- Standardized KQL field names in `high-volume-blocks.json` alert rule to use `OperationType_s`/`ActionTaken_s` (matching KQL queries)
- Fixed enforcement mode trace message in `ValidateMimeTypePlugin.cs` — now shows actual mode instead of hardcoded "LogOnly"
- Corrected alert frequency documentation from "Every 5 minutes" to "Every 1 hour" (matching actual PT1H)
- Corrected MITRE ATT&CK reference from T1566.001 to T1566 + T1204 (matching alert rule JSON)

### Added
- Rollback procedure in SOLUTION-DOCUMENTATION.md (3 options: disable step, change mode, unregister)
- PAC CLI deployment commands as alternative to Plugin Registration Tool
- Design decisions section documenting intentional exclusions (legacy Office, SVG, rate limiting)
- PowerShell module (FsiMimeControl) documentation in SOLUTION-DOCUMENTATION.md, README.md, and DELIVERY-CHECKLIST.md

## [1.0.0] — February 2026

### Added
- Dataverse plugin (`ValidateMimeTypePlugin.cs`) for server-side MIME type validation
- DLP policy template (`dlp-policy-template.json`) for policy-based MIME restrictions
- MIME configuration file (`MimeConfig.json`) for allowlist/blocklist management
- Sentinel query (`query-mime-blocks.kql`) for blocked MIME type event monitoring
- Sentinel alert rule (`high-volume-blocks.json`) for high-volume block pattern detection
- Sentinel query (`query-exception-usage.kql`) for exception usage tracking
- All 6 artifacts migrated from FSI-AgentGov `src/` to FSI-AgentGov-Solutions
