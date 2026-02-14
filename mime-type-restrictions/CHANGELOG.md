# Changelog

All notable changes to MIME Type Restrictions for File Uploads are documented here.

## [1.0.0] — February 2026

### Added
- Dataverse plugin (`ValidateMimeTypePlugin.cs`) for server-side MIME type validation
- DLP policy template (`dlp-policy-template.json`) for policy-based MIME restrictions
- MIME configuration file (`MimeConfig.json`) for allowlist/blocklist management
- Sentinel query (`query-mime-blocks.kql`) for blocked MIME type event monitoring
- Sentinel alert rule (`high-volume-blocks.json`) for high-volume block pattern detection
- Sentinel query (`query-exception-usage.kql`) for exception usage tracking
- All 6 artifacts migrated from FSI-AgentGov `src/` to FSI-AgentGov-Solutions
