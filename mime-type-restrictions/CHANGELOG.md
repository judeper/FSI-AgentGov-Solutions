# Changelog

All notable changes to MIME Type Restrictions for File Uploads are documented here.

## [1.1.0] — 2026-04-17 — BREAKING (control-coverage scope reduction)

### Changed (BREAKING)

- **Primary controls reduced** from 9 to 5. The solution previously claimed
  controls 1.10 (Communication Compliance), 1.11 (Conditional Access /
  MFA), 1.14 (Content Moderation Enforcement) and 4.3 (SharePoint
  Oversharing Prevention) — none of which are actually implemented by
  this artifact set. Removed those over-claims from the README. Retained
  primary controls: **1.5, 1.13, 1.25, 3.3, 3.7**.

### Added

- **Plugin: hard-deny denylist for executable / script extensions** —
  `.ps1`, `.bat`, `.cmd`, `.exe`, `.js`, `.vbs`, `.jar`, `.py`, `.sh`
  and ~25 others are blocked regardless of declared MIME type. Closes a
  bypass where a script file declared as `text/plain` would have passed
  the allowlist + binary-content check.
- **Plugin: filename-extension-vs-MIME-type cross-check** — the
  declared MIME type's allowlist entry now constrains which filename
  extensions are permitted, catching mislabeled files even when the
  MIME type itself is allow-listed.
- **Plugin: subtype-aware OpenXML inspection** — `wordprocessingml`,
  `spreadsheetml` and `presentationml` MIME types now require the
  corresponding `word/`, `xl/` or `ppt/` package directory inside the
  ZIP (in addition to `[Content_Types].xml`). A bare ZIP that only
  contains `[Content_Types].xml` no longer satisfies the check.
- **Flow doc:** Pre-Image registration is now an explicit, required
  step. Without a `PreImage` (mimetype + filename) on the Update step,
  partial updates that omit those columns are fail-secure-blocked by
  the plugin.
- **Delivery checklist:** matching Pre-Image entry added to the plugin
  registration checklist.

### Fixed

- **DLP template clarified as conceptual, not deployable.** The file
  `templates/dlp-policy-template.json` previously appeared importable
  via `New-AdminDlpPolicy`. It is now prominently marked as a
  reference document — Power Platform DLP cannot enforce extension or
  MIME-type rules directly; it only classifies connectors. The flow
  doc's "Step 3" was rewritten to translate the reference into
  connector classifications via the admin center / Set-DlpPolicy.
- **Removed fictional PAC CLI commands.** `pac plugin push` and
  `pac plugin step create` do not exist in any current PAC CLI release.
  The "Step 2 (Alternative)" section now redirects users to the
  Plugin Registration Tool (PRT) and `pac solution import` for CI/CD.

### Notes

- Council review (April 2026) findings closed for this solution.

---

## [1.0.2] — 2026-04-10

### Changed
- Restructured solution to follow standard layout
- Moved documentation from root and src/ to docs/
- Moved KQL queries to scripts/
- Moved JSON templates to templates/
- Retained C# plugin source code in src/

## [1.0.1] — 2026-02-20

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

## [1.0.0] — 2026-02-01

### Added
- Dataverse plugin (`ValidateMimeTypePlugin.cs`) for server-side MIME type validation
- DLP policy template (`dlp-policy-template.json`) for policy-based MIME restrictions
- MIME configuration file (`MimeConfig.json`) for allowlist/blocklist management
- Sentinel query (`query-mime-blocks.kql`) for blocked MIME type event monitoring
- Sentinel alert rule (`high-volume-blocks.json`) for high-volume block pattern detection
- Sentinel query (`query-exception-usage.kql`) for exception usage tracking
- All 6 artifacts migrated from FSI-AgentGov `src/` to FSI-AgentGov-Solutions
