# Changelog

All notable changes to the Hallucination Feedback Tracker.

---

## [1.1.0] - 2026-04-17

### Fixed

- **Critical:** `Get-HallucinationSummary.ps1` returned a green `Healthy` status when `fsi_hallucinationreports` had zero records, masking missing telemetry, broken feedback flows, or revoked permissions. Status now defaults to `NoData` when `$totalReports -eq 0`.
- **Critical:** `docs/source-configuration.md` omitted three `ApplicationRequired` columns (`fsi_reportname`, `fsi_category`, `fsi_severity`) — every Power Automate flow built per the prior doc would fail on insert with `RequiredFieldValueMissing`. Doc now includes a mandatory-fields callout and explicit category/severity integer mapping tables per source.
- **High:** `analyze_patterns.py` per-agent score formula was mislabeled as an "accuracy" score; the denominator is the agent's hallucination report count, not response count. Renamed and documented as a *risk score*; agents with fewer than 3 reports return `InsufficientData`.
- **High:** Hard-coded Dataverse-domain allowlist in `analyze_patterns.py` rejected legitimate regions (e.g., `crm10.dynamics.com`) and sovereign clouds. Replaced with a regex matching all `*.crm\d*.dynamics.com`, `*.microsoftdynamics.us`, `*.appsplatform.us`, `*.dynamics.cn`, and `*.dynamics.de` hosts.
- **High:** Overall-status logic in `Get-HallucinationSummary.ps1` raised `Warning` for any category cluster regardless of severity. `Warning` now requires at least Medium-or-higher severity volume; pure-Low category clusters surface as `Review`.
- **Medium:** Renamed `HallucinationRate` to `ShareOfReports` in summary output (the metric was share-of-reports, not a true rate).
- **Medium:** `Export-HallucinationEvidence.ps1` now includes `fsi_reportname` in the readable projection (was queried but dropped).
- **Medium:** `Test-EvidenceIntegrity.ps1` `[ValidateScript]` on `-EvidenceFilePath` blocked `-Quiet` automation; validation moved inside `try/catch` so `-Quiet` returns a clean `$false`.
- **Medium:** Regulatory citations standardized in README: `FINRA 2210` → `FINRA Rule 2210 — Communications with the Public`; `SEC Marketing Rule` → `SEC Rule 206(4)-1 (Investment Adviser Marketing Rule)`.
- **Medium:** README quick-start commands now include required `AZURE_TENANT_ID`/`AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET` env vars and `--environment` URL.
- **Medium:** README "Trend Analysis: Implemented" claim narrowed — Python analyzer is point-in-time only.

### Changed

- Status taxonomy in `Get-HallucinationSummary.ps1` extended with `NoData` and `Review` entries.
- `MIN_REPORTS_FOR_SCORE = 3` threshold added to `analyze_patterns.py` agent scoring.

---

## [1.0.0] - 2026-04-10

### Added
- Dataverse schema deployment script with 1 table, 3 option sets, and `--output-docs` support
- Environment variables script (7 variables for analysis config, notifications)
- Connection references script (Dataverse + Teams)
- PowerShell governance scripts: Export-HallucinationEvidence (SHA-256), Test-EvidenceIntegrity, Get-HallucinationSummary
- Auto-generated Dataverse schema documentation

### Changed
- Graduated from v0.1.0-preview to v1.0.0 with full deployment scripts and governance automation

---

## [0.1.0-preview] - 2026-02-15

### Added

- Initial release of Hallucination Feedback Tracker
- **Feedback Source Schema** (specification only — collection flows not yet implemented):
  - User thumbs-down reactions
  - Supervisor rejections from FSW
  - Automated verification checks
  - Customer complaints
- **Hallucination Categories:**
  - Factual error
  - Fabricated data
  - Citation missing
  - Outdated information
  - Confidence overstatement
- **Pattern Analysis:**
  - Category clustering
  - Agent-specific patterns
  - Severity distribution
- **Python Scripts:**
  - `analyze_patterns.py` - Pattern detection
- **Agent Scoring:**
  - Accuracy score calculation
  - Rating system (Excellent/Good/Needs Improvement/Critical)
- **Documentation:**
  - Prerequisites and licensing
  - Source configuration guide
  - Pattern analysis methods

### Regulatory Alignment

- FINRA 2210 - Communications accuracy
- SEC Marketing Rule - Substantiation
- CFPB Chatbot Guidance - Accuracy

---

*Hallucination Feedback Tracker v1.0.0 - FSI Agent Governance Framework*
