# Changelog

All notable changes to the Compliance Dashboard solution.

---

## [Unreleased]

## [1.0.4] - 2026-05-17

### Changed

- Bumped solution metadata to v1.0.4 for the Microsoft Learn 2026-Q2 refresh.
- Reframed Purview Compliance Manager integration as portal export/manual evidence import until Microsoft publishes a supported Compliance Manager Graph API or SDK for assessment score export.
- Updated authentication guidance to managed identity / DefaultAzureCredential first, with client-secret fallback marked as legacy dev-only.
- Added Microsoft Graph reports, Power BI REST, Dataverse aggregation, and Exchange Online Security & Compliance PowerShell guidance aligned with current Microsoft Learn documentation.
- Corrected the manifest tier to Tier 2 and clarified that the dashboard reports across the 78-control baseline when those records are loaded.

### Fixed

- Removed instructions to store Power BI `.pbix` / `.pbit` binaries in the repository.
- Updated Exchange collector metadata to include control 3.4 with the rest of the dashboard control mapping.

---

## [1.0.3] - 2026-04-16

### Fixed (AI Council deep review)

- **Lookup column DAX references** in `docs/dax-measures.md` and `docs/power-bi-template-spec.md` — the Power Query Dataverse connector imports lookup columns as `_<schemaname>_value` GUID columns on the child side. Replaced direct `[fsi_controlmasterid]`/`[fsi_controlassessmentid]` references on `ControlAssessment`, `ComplianceEvidence`, and `ComplianceException` with the underscore-prefixed `_value` form to match the connector’s schema. Updated all three model relationships in `power-bi-template-spec.md` accordingly.
- **`Compliant Controls` measure inflation** in `docs/power-bi-template-spec.md` — the legacy `CALCULATE(COUNTROWS(ControlAssessment), ...)` form counts every historical assessment (90 days × N zones per control). Added a prominent note pointing readers to the `LatestAssessments`-based pattern in `dax-measures.md` for accurate "current state" counts.
- **Invalid `Pillar Names` DAX expression** in `power-bi-template-spec.md` — `Pillar Names = {"Security", ...}` is not valid as a calculated column or measure. Replaced with a reference to the existing `PillarDimension` `DATATABLE` defined in `dax-measures.md`.
- **Invalid RLS pseudocode** in `power-bi-setup.md` and `power-bi-template-spec.md` — `[Zone] = VALUE(USERPRINCIPALNAME())` and `[Pillar] IN { IF(USERPRINCIPALNAME()=…, n) }` cannot work in production (UPN is a string, not numeric, and `IF` inside `IN` collapses to BLANK on the false branch). Marked both blocks as pseudocode and showed the production pattern: load a UPN→Zone / UPN→Pillar mapping table and join via `CALCULATETABLE(VALUES(...), Mapping[Upn] = USERPRINCIPALNAME())`.
- **Missing `ConsistencyLevel: eventual` header** in `Get-ExchangeComplianceData.ps1` — Microsoft Graph advanced queries (`$count=true`, `assignedLicenses/$count`, `mailboxSettings/userPurpose` filtering) require `ConsistencyLevel: eventual`. Added a `Headers` parameter to the helper functions and emit the header on the two affected callers.
- **Server `Retry-After` honored on 429/503** in `Get-ExchangeComplianceData.ps1` — previous exponential backoff ignored Graph’s server-side retry guidance. Now reads `Retry-After` (seconds) when present and waits at least that long before retrying.
- **`fsi_controlassessments` plural** corrected to `fsi_controlassessment` in `flow-configuration.md` — Dataverse logical names are singular and the entity set name in the schema script is the singular form pluralized by Dataverse internally; OData binds and lookup nav-prop names use the singular schema name.
- **Environment-variable prefix consistency** in `flow-configuration.md` — standardized on the `fsi_CD_*` prefix for all CD env vars (display name vs schema name was previously inconsistent), and added a note distinguishing schema name (used in expressions) from display name (used in the picker).
- **Power Automate calculated-column writes** in Flow 2 SLA pseudo-code rewritten to clarify that `fsi_daysopen` and `fsi_slastatus` are read-only calculated columns; the flow updates the inputs (target date, severity) and lets Dataverse recompute.
- **`fsi_controlid` field on assessment/exception payloads** in `scripts/load_sample_data.py` is documented as a known limitation: the schema uses a lookup (`fsi_ControlMasterId`) which requires `@odata.bind` resolution, not a string FK. The exporter still produces JSON for inspection; a complete loader requires GUID lookup + `@odata.bind`. Documented integer option-set value mismatch (1/2/3 vs 100000000+) in the same docstring.
- **Missing Microsoft Graph permissions** in `prerequisites.md` — added `User.Read.All`, `Group.Read.All`, `MailboxSettings.Read`, `Mail.Read`, and `SecurityAlert.Read.All` for the Exchange compliance signals collected by `Get-ExchangeComplianceData.ps1`.
- **Missing Dataverse Application User step** in `prerequisites.md` — added an explicit step in Power Platform admin center to grant the app registration Dataverse access (System Customizer + Basic User).
- **Service-admin role naming** — renamed the `Microsoft Entra ID Roles` heading to `Service Admin Roles` and added Exchange Online Admin as a supporting role for interactive runs of the data collector.
- **Stale dependency versions** in `prerequisites.md` — bumped `environment-lifecycle-management` to v1.1.3, `finra-supervision-workflow` to v1.0.1, `deny-event-correlation-report` to v2.0.1.
- **Sample-data overclaim** — README, deployment-checklist, troubleshooting, dataverse-schema, and template-spec all previously implied 78 controls were shipped. Reframed: the sample dataset contains 62 controls; the validated framework baseline contains 78. Documentation now distinguishes "load the sample" vs "load the baseline" and updates the verification step counts accordingly.
- **`.pbit` download references** removed from `power-bi-setup.md` and `deployment-checklist.md` — per the Solution Content Policy, no `.pbit` ships with the repo. Both docs now point to `power-bi-template-spec.md` for build instructions.
- **"Score Trend" naming drift** in `power-bi-setup.md` aligned to the canonical name `Score Change 30D` used in `dax-measures.md`.
- **Choice column axis warning** in `power-bi-template-spec.md` — added a note that `fsi_slastatus` and similar choice columns are imported as integer option-set values; either rebind to the connector’s `*_label` alias column or join to a status dimension table for friendly labels.
- **Stale solution-package import language** in `flow-configuration.md` — removed; replaced with the manual build flow per content policy. Cleaned the Known Limitations table of orphan entries (`Customizations.xml`, `[Content_Types].xml`, dead env-var references).
- **Stale Connection Reference list** in `flow-configuration.md` — corrected to Dataverse + Office 365 Outlook + Microsoft Teams; removed the spurious HTTP-Entra mention.
- **Regulatory wording** in README rewritten with proper section citations (FINRA 3120(a)(1) reasonably-designed, OCC 2011-12 / SR 11-7 model classification, SOX 302 vs 404 distinction) and softened to "supports compliance with" / "helps meet" per repo language rules.
- **Control mapping** updated to `3.3, 3.1, 3.2, 3.4` in the catalog tables (Compliance Reporting → 3.4 Deny Event Correlation is materially aggregated by this dashboard).
- **Generic `contoso` references** replaced with `tenant` / `example` (RFC 2606) across README, scripts, template-spec, and setup docs.
- **Inactive-shared-mailbox phrasing** in README aligned to what `Get-ExchangeComplianceData.ps1` actually emits.
- **Footers and `Get-ExchangeComplianceData.ps1` banner** bumped to v1.0.3 across docs.
- **`templates/exchange-config.sample.json`** version bumped to v1.0.3 and `riskThresholds` / `scanScope` keys documented as reserved for future configurability.

### Known Limitations

- `scripts/load_sample_data.py` still emits string `fsi_controlid` on assessment/exception payloads. Dataverse will reject these because the schema defines a lookup (`fsi_ControlMasterId`); use `--export` only until a follow-up patch implements GUID lookup + `@odata.bind`. See the script docstring for details.

---

## [1.0.2] - 2026-04-15

### Fixed

- Removed stale ZIP import instructions from README and dataverse-schema.md (package was removed in v1.0.1)
- Updated Get-ExchangeComplianceData.ps1 version strings to v1.0.2

---

## [1.0.1] - 2026-03-15

### Removed

- **Exported Dataverse solution package** (`src/ComplianceDashboard/`) removed per repository content policy — solutions must not contain Power Platform runtime artifacts (flow JSON, connection references, environment variable exports)
- Updated `templates/README.md` to reference manual build instructions instead of `src/` import

### Note

All flow logic remains fully documented in [Flow Configuration](docs/flow-configuration.md). Administrators should build flows manually in Power Automate designer following that guide.

---

## [1.0.0] - 2026-02-04

### Added

- **Deployment Documentation:**
  - Comprehensive deployment checklist with manual validation steps
  - Power BI template creation specification (.pbit manual creation guide)
  - Known limitations section documenting what is not supported
  - Rollback and uninstall procedures
- **Power Platform Solution Package:**
  - Unmanaged solution package (ComplianceDashboard_1_0_0.zip)
  - Contains Dataverse schema and Power Automate flows
  - Connection reference configuration for Dataverse, Outlook, Teams
  - Environment variables for notification email and Teams webhook
- **Enhanced Sample Data:**
  - Full 62-control coverage with zone applicability
  - 90-day historical compliance score data for trend analysis
  - Realistic distributions (not uniform scores)
  - Sample exceptions with varied SLA statuses and severities
  - Export flag for sample data extraction

### Changed

- **Status:** Updated from beta (v1.0.0-beta) to production-ready (v1.0.0)
- **README:** Restructured with Known Limitations and Rollback sections
- **Quick Start:** Updated to reference actual solution package and deployment checklist
- **Documentation:** Added deployment-checklist.md and power-bi-template-spec.md to documentation table

### Fixed

- Sample data loader now generates realistic compliance score variations
- Clarified that RLS is not pre-configured (customer must implement)
- Documented manual .pbit creation requirement

---

## [1.0.0-beta] - February 2026

### Added

- Initial release of Compliance Dashboard
- **Dataverse Schema:**
  - `fsi_controlmaster` - 62 framework controls with zone applicability and weights
  - `fsi_controlassessment` - Assessment records with status and scores
  - `fsi_compliancescore` - Daily compliance score snapshots
  - `fsi_complianceexception` - Exception tracking with SLA management
  - `fsi_complianceevidence` - Evidence collection with integrity hashing
- **Security Roles:**
  - CD Viewer - Read-only dashboard access
  - CD Assessor - Assessment entry and exception management
  - CD Admin - Full administrative access
- **Power Automate Flows:**
  - CD-ScoreCalculator - Daily compliance score calculation
  - CD-ExceptionMonitor - Hourly SLA status monitoring
  - CD-EvidenceCollector - Design documented in flow-configuration.md (planned — no flow definition exists in the solution package yet)
- **Power BI Dashboard:**
  - Executive Summary page
  - Pillar Overview page
  - Control Details page with drill-through
  - Exception Tracker page
  - Trend Analysis page
- **Documentation:**
  - Prerequisites and licensing requirements
  - Dataverse schema definitions
  - Flow configuration guide
  - Power BI setup and customization
  - DAX measure library
  - Troubleshooting guide
- **Sample Data:**
  - Control master JSON (62 controls)
  - Python script for loading sample data

### Regulatory Alignment

- SOX 404 (ICFR documentation)
- FINRA 3120 (supervisory control testing)
- OCC 2011-12 (model risk reporting)

---

*Compliance Dashboard - FSI Agent Governance Framework*
