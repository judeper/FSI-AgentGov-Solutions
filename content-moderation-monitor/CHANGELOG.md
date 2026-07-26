# Changelog

All notable changes to the Content Moderation Monitor.

## [Unreleased]

### Validated

- **Live tenant validation completed 2026-06-13 against the lab validation tenant (lab evidence).** The three CMM tables (29 columns; `fsi_severity` as a String, `fsi_zone` bound to the canonical `fsi_acv_zone` set) were deployed and verified, and the bot-config-STATE detector (`aISettings.contentModeration`) was exercised on disposable-bot fixtures: a Zone 1 fixture below the minimum (`contentModeration="Low"`) flagged Critical and persisted (`fsi_zone=100000001`, `fsi_severity="Critical"`), a compliant fixture (`contentModeration="High"`) produced no row, a same-fixture flip discriminated, and an absent node resolved to Unknown (never a false Compliant), with a real-agent cross-check. The SHA-256 evidence digest recomputed to an integrity match (prefix `E7006488…`); all disposable fixtures were torn down (the three CMM tables back to 0, orphaned botcomponents removed, the two real agents untouched) and the deployed schema is retained as the deliverable. Coverage stays **PARTIAL** (bot-config STATE only; runtime moderation telemetry, Purview moderation logs, prompt-tool overrides, and voice-modality moderation remain out of lab scope). This is lab evidence on disposable fixtures, not proof of behavior in a customer's production tenant. See `LAB-VALIDATION.md` "Live tenant validation outcome (2026-06-13)".

### Fixed

- **Major**: `scripts/create_dataverse_schema.py` schema-deploy defects surfaced during the 2026-06-13 live deploy. The primary-name attribute was not flagged (`IsPrimaryName=true` now set inline), the `fsi_zone` picklist bind was sent by option-set Name (the resolver now rewrites it to the option-set GUID), and a stray `OptionSet: null` was emitted alongside the bind (removed). With these fixes the 3-table schema deploys idempotently on the lab validation tenant. (live deploy 2026-06-13)
- **Critical**: `Get-BotModerationLevel` (in `scripts/private/CMMClient.psm1`) read the content-moderation level from flat, top-level `bot.configuration` keys (`ContentModeration` / `contentModeration` / ...) that do not exist on real Copilot Studio agents. Against live lab-tenant agents this returned `Unknown` for every agent (zero violations) while a fixture authoring those keys went green tautologically. Re-pathed the detector to the real **nested** `aISettings.contentModeration` key (confirmed read-only on the live lab validation tenant 2026-06-13: a string level such as `High`). Defensive by design: an absent `aISettings`/`contentModeration` node resolves to `Unknown` — never a false-Compliant. (zone/severity reconciliation, Option A)
- **Minor**: `docs/flow-setup.md` listed the license as "Power Automate Premium per user." The current Microsoft SKU name is **Power Automate Premium** (sold per user); "per user" is the licensing model, not part of the SKU name. Relabeled to "Power Automate Premium, which is sold per user." Verified against [Types of Power Automate licenses](https://learn.microsoft.com/power-platform/admin/power-automate-licensing/types). (Microsoft Learn accuracy review)
- **Major**: `correlate_purview_events.py` passed invalid `recordTypeFilters` values (`CopilotInteraction`, `PowerPlatform`) to the Microsoft Graph `auditLogQuery` API. Neither is a valid `microsoft.graph.security.auditLogRecordType` enum member, so the query would be rejected. Copilot interactions are now selected via `operationFilters: ["CopilotInteraction"]` (unified audit log RecordType 261), the documented way to target Copilot interaction events. Added `operation_filters` support to `create_audit_log_query` and updated the README correlation description. (lab-readiness validation)
- **README technical re-verification (`Last Verified` 2026-05-25 → 2026-07-26).** Re-checked every Microsoft product claim in `README.md` against current Microsoft Learn documentation. Still accurate: Copilot Studio moderation levels range from **Lowest** to **Highest** (platform default **High**), with topic-level and prompt-tool overrides; the Microsoft Graph `auditLogRecordType` v1.0 enum still exposes no dedicated Copilot member, so `operationFilters` remains the correct selector; unified audit log `CopilotInteraction` is still RecordType 261 with workload `Copilot`; `AuditLogsQuery.Read.All` and the service-scoped `AuditLogsQuery-CRM.Read.All` are both still valid; Azure AI Content Safety still ships Prompt Shields, Groundedness detection, Protected material text detection, and the Task adherence API; and `Microsoft.PowerApps.Administration.PowerShell` / `Add-PowerAppsAccount` are still the documented Power Platform admin entry point.
- **Minor**: The voice-agent platform note cited `microsoft-copilot-studio/voice-configuration`, which Microsoft has since narrowed to *Configure basic voice agents*. The voice documentation now splits into an IVR overview (`voice-overview`) plus separate **basic voice agents** and **real-time agents** tracks. Re-pointed the citations, replaced the stale "Basic and Realtime voice modes" phrasing with Microsoft's current terminology, and added two verified product facts: Microsoft's responsible AI notice that real-time agents carry a higher risk of producing potentially harmful content, and its documented limitation that transcript logging for Text LLM voice agents may omit conversation turns.
- **Minor**: The scope note described the Graph agent-package endpoints as "Microsoft 365 Copilot package management APIs ... currently preview." Microsoft now documents them as the **Agent 365 Package Management API**, gated on a Microsoft Agent 365 license and the AI Administrator or Global Administrator role, with list/get generally documented and the write operations (update, block, unblock, reassign) marked preview. Updated the wording accordingly; the conclusion is unchanged — these APIs return package metadata, not the Copilot Studio agent-default moderation field.

### Changed

- **Critical**: Aligned CMM's governance-zone semantics to the **canonical (Option A)** meaning of the shared `fsi_acv_zone` set, established by the producing schema (`agent-intake`) and the live lab validation tenant: **Zone 1 (Enterprise) is the MOST-restrictive tier (`100000001`)** and **Zone 3 (Personal) the LEAST (`100000003`)** — the inverse of CMM's prior model. Flipped the policy table (`templates/moderation-baseline.json`: Zone 1 ⇒ Enterprise Managed / High minimum / Critical-severity FINRA + GLBA violations; Zone 3 ⇒ Personal Productivity / Medium minimum), the naming-convention map in `scripts/private/Get-ZoneClassification.ps1` (enterprise/prod ⇒ Zone 1, personal/dev/sandbox ⇒ Zone 3), the shared `scripts/shared/Get-ZoneClassification.ps1` naming patterns, the Zone-1 weakened-drift escalation in `Start-ModerationValidationRunbook.ps1`, and all zone-semantic text in README/SOLUTION-DOCUMENTATION/DELIVERY-CHECKLIST/docs. The integer write map (`Zone1→100000001 … Zone3→100000003`) and the `fsi_severity` String column were already canonical and are unchanged. Added `tests/ModerationZoneCanonical.Tests.ps1` asserting "strictest moderation ⇔ Zone 1 ⇔ 100000001" and the defensive nested re-path. (zone/severity reconciliation, Option A — accepted 2026-06-13)

## [1.1.2] - 2026-05-22

### Fixed

- **Critical**: `correlate_purview_events.py` called the nonexistent `DataverseClient.get_records()` method. Now uses `client.query()` with a list-typed `select` parameter. (council review C-01)
- **Critical**: `correlate_purview_events.py` referenced columns that do not exist on `fsi_moderationviolations`: `fsi_moderationlevel` (correct: `fsi_actuallevel`) and `fsi_environmentid` (correct: `fsi_environmentguid`). (council review C-02)
- **Major**: `correlate_purview_events.py` instantiated `DataverseClient` without an `auth_mode`, causing a `ValueError` at runtime because the default `client-secret` path required `client_id`/`client_secret` not being supplied. Added `--auth-mode`/`--client-id`/`--client-secret` CLI wiring so managed identity, workload identity, and client-secret all work. (council review M-03)
- **Major**: `Export-ContentModerationEvidence.ps1` passed `Zone` values (`'1'`, `'2'`, `'3'`) directly to `Get-CMMValidationResults` whose `ValidateSet` accepts only `'Zone1'`, `'Zone2'`, `'Zone3'`, `'Unknown'`, `'All'`. Zone-filtered exports now map `'N'` to `'ZoneN'` before invoking the query. (council review M-01)
- **Major**: `Invoke-ModerationBaselineCapture.ps1` `.NOTES` block said "PowerShell 5.1 or later" while the `#Requires -Version 7.0` directive and `??` operator usage require PS 7.0+. Notes now match. (council review M-02)

### Changed

- **Minor**: Synced internal version strings from `1.0.0` to `1.1.2` in `Test-ContentModerationCompliance.ps1` (NOTES + verbose banner) and `Export-ContentModerationEvidence.ps1` (NOTES). (council review m-01, m-02)

## [1.1.1] - 2026-05-17

### Added

- **Purview Audit / DSPM correlation.** New `correlate_purview_events.py` script correlates moderation violations with Purview unified audit log events and DSPM signals. Queries Purview Audit via Graph `auditLogQuery` API, matches events by user + timestamp proximity (5-minute window), and enriches output with sensitivity labels, DLP policy matches, and Copilot interaction context. Requires `AuditLogsQuery.Read.All` and `User.Read.All` Graph permissions.

### Changed

- Bumped solution manifest to 1.1.1 for the Microsoft Learn 2026-Q2 technical review.
- Corrected manifest controls to `1.27` primary and `1.8` complementary so generated catalogs match the framework mapping.
- Added moderation-level aliases for Copilot Studio `Lowest` and `Highest` labels, normalizing them to CMM's canonical `Low` and `High` scale.
- Clarified managed identity-first authentication guidance; client-secret service principal auth remains a legacy development fallback only.
- Documented that CMM audits agent-default Copilot Studio moderation configuration and does not call Azure AI Content Safety runtime APIs, Microsoft Graph package-management preview endpoints, or Purview runtime audit feeds.

## [1.1.0] - 2026-04-17

AI Council technical-accuracy review (Opus 4.7 + Goldeneye + GPT-5.4) plus targeted
researcher follow-up on Copilot Studio moderation field surface and FSI control
mappings. This release contains documentation/bug fixes only — no schema changes.

### Fixed

- **Critical (latent runtime):** `CMMClient.psm1` `Write-ModerationViolation` and
  `Save-CMMBaseline` zone-fallback wrote `0` to `fsi_zone` for unknown zone strings.
  The `fsi_acv_zone` global option set's valid range is `100000000`–`100000003`, so
  every write with an unknown zone was silently rejected by Dataverse with a
  BadRequest. Fallback now writes `100000000` (Unknown). An `'Unclassified' = 100000000`
  alias was also added to `$script:ZoneToInt` so the schema label and the runtime
  hashtable round-trip cleanly.
- **High:** `Get-ZoneClassification.ps1` standalone-fallback path was unreachable
  (wrong relative path to the shared utility — `..\..\` instead of `..\..\..\`)
  AND the local Dataverse fallback mapped `fsi_zone` as `1/2/3` instead of the
  real option-set values `100000001/100000002/100000003`. Both fixed.
- **High:** `Invoke-ModerationBaselineCapture.ps1` declared `#Requires -Version 5.1`
  but used the PowerShell 7 null-coalescing operator (`??`), causing parse failure
  on Windows PowerShell 5.1. Bumped requirement to `-Version 7.0` to match runtime.
- **High:** `Get-AgentModerationSettings.ps1` called `Get-AdminPowerAppEnvironment`
  with no Power Platform connection precondition. Catch block now surfaces a
  friendly hint to run `Add-PowerAppsAccount` (or pass an SP context) when
  authentication is the failure cause.
- **High:** Control mapping was wrong. README and SOLUTION-DOCUMENTATION claimed
  Control `1.14 (Content Moderation Enforcement)`, but framework Control 1.14 is
  **Data Minimization**. Actual moderation control is **1.27 (AI Agent Content
  Moderation Enforcement)**. README and Related Controls table now lead with 1.27
  primary and re-position Control 1.8 as **complementary** (CMM contributes one
  config-time signal; 1.8 is broader runtime protection). v1.0.3 had silently
  reverted 1.27 → 1.14 with no CHANGELOG entry; this release re-corrects to 1.27.
- **High:** `docs/FLOW_SETUP.md` Step 1 said "Import from JSON (Recommended)" but
  no flow JSON ships (removed in v1.0.2 per content policy). Rewritten as
  manual scheduled-flow build instructions. Overview bullet that claimed the
  flow itself "writes validation results to Dataverse" was corrected — the flow
  triggers the runbook that performs the writes.
- **High:** `docs/EVIDENCE_EXPORT.md` sample JSON did not match script output:
  fictional `baselineId` field removed, violation `zone` shown as raw option-set
  integer (`100000003`) to match `Export-ContentModerationEvidence.ps1` behavior,
  and `recordCount` aligned with `totalScans` semantics.
- **High:** `SOLUTION-DOCUMENTATION.md` claimed extraction of a documented
  `contentModerationLevel` property. The code actually probes four possible keys
  (`ContentModeration`, `contentModeration`, `ContentModerationSetting`,
  `contentModerationSetting`) on an undocumented `bot.configuration` blob. Doc now
  describes the heuristic honestly and adds a "best-effort, scope-limited" caveat.
  README has a new **Scope and Limitations** section that explicitly lists what
  CMM does NOT cover (topic-level overrides, custom safety messages, Purview
  moderation logs, runtime moderation decisions).
- **Medium:** `docs/SCHEMA.md` table headings used entity-set names but listed
  singular-logical primary keys. Now show both **Logical name** and **Entity set
  (OData)** explicitly so OData URL builders and Web API callers don't conflate
  the two.
- **Medium:** `Get-CMMValidationResults.ps1` `-Zone` ValidateSet was
  `'All','1','2','3'` (dropped Unknown and used integer-string labels). Now
  `'All','Zone1','Zone2','Zone3','Unknown'` matching the schema label set; int
  map updated with `Unknown = 100000000`.
- **Medium:** `docs/PREREQUISITES.md` listed MSAL.PS as required but the
  Installation block omitted it. Added pinned `Install-Module -Name MSAL.PS
  -RequiredVersion 4.37.0`. PowerShell floor raised to 7.2+ to match runbook
  target and the `??` operator usage.
- **Medium:** `CMMClient.psm1` doc-comment for `Get-BotModerationLevel` claimed
  a botcomponent fallback path. The scan pipeline never retrieves component
  records, so the fallback is dead code. Comment now describes `-Components`
  as a future-use parameter and warns that component-only agents will resolve
  to `Unknown` today.
- **Low:** Stripped `(formerly Azure AD)` parentheticals from live scripts and
  docs (`Connect-EnvironmentDataverse.ps1`, `Export-ContentModerationEvidence.ps1`,
  `Invoke-ModerationBaselineCapture.ps1`, `Start-ModerationValidationRunbook.ps1`).
- **Low:** Replaced `contoso.onmicrosoft.com` / `admin@contoso.com` with RFC 2606
  `example.onmicrosoft.com` / `admin@example.com` across all docs and scripts.
- **Low:** README Quick Start `Install-Module` now uses `-Scope CurrentUser`.
- **Low:** `FLOW_SETUP.md` "Power Automate Premium" relabeled "Power Automate
  Premium per user" (per-user is the actual SKU name) with link to current
  Microsoft licensing reference.

### Known limitations

- MSAL.PS is community-maintained and unchanged since 4.37.0 (2022). Microsoft
  recommends `Az.Accounts` `Get-AzAccessToken` for new code. CMM still hard-pins
  MSAL.PS 4.37.0 in three runbooks; migration to Az.Accounts is deferred.
- Copilot Studio moderation level is read from an undocumented `bot.configuration`
  JSON blob via heuristic key probing. If Microsoft renames the field, agents
  will resolve to `Unknown` (treat as **unverified**, not compliant).

## [1.0.3] - 2026-04-15

### Fixed

- Critical: Test-ContentModerationCompliance Write-Output changed to Write-Host in Object mode to prevent pipeline contamination (string was mixed into scan results, corrupting counts in runbook)

## [1.0.2] - 2026-07-14

### Changed
- Moved `src/adaptive-card-moderation-alert.json` to `templates/` per solution content policy
- Updated README, DELIVERY-CHECKLIST, FLOW_SETUP, and SOLUTION-DOCUMENTATION to reflect new paths

### Removed
- `src/moderation-validation-flow.json` — Replaced by manual build instructions in `docs/FLOW_SETUP.md`
- `src/dataverse/` scaffolding (empty placeholder directories and README) — Schema deployed via `scripts/create_dataverse_schema.py`
- `src/` directory entirely

## [1.0.1] - 2026-02-15

### Fixed
- Corrected primary control reference from 1.14 to 1.27 (AI Agent Content Moderation Enforcement) in README.md and SOLUTION-DOCUMENTATION.md
- Fixed Related Controls URL slug to `1.27-ai-agent-content-moderation-enforcement/`
- Added explicit `src/` path prefix to flow file reference in DELIVERY-CHECKLIST.md
- Fixed FSI language compliance: "Ensure consistent" → "Help ensure consistent" in SOLUTION-DOCUMENTATION.md and DELIVERY-CHECKLIST.md

### Removed
- Empty `flows/` directory (flow file lives in `src/moderation-validation-flow.json`)

### Added
- `src/dataverse/README.md` explaining placeholder subdirectories and programmatic schema deployment

## [1.0.0] - 2026-02-10

### Added — Phase 4: Evidence Export & Framework Integration
- `Export-ContentModerationEvidence.ps1` — SHA-256 integrity-hashed compliance evidence export with zone filtering, date range, baseline inclusion, and interactive/service principal authentication
- `Get-CMMValidationResults.ps1` — Dataverse query helper for validation history and violations with OData pagination, zone filtering, and RunId support
- `Test-EvidenceIntegrity.ps1` — Evidence integrity verification utility comparing computed SHA-256 against companion hash file
- Control 1.8 tip admonition linking to Content Moderation Governance Monitor solution
- solutions-index.md catalog entry with components, regulatory alignment, and repository link
- `docs/SCHEMA.md` — Complete Dataverse schema reference (3 tables, option sets, environment variables, connection references, entity relationship diagram)
- `docs/EVIDENCE_EXPORT.md` — Step-by-step evidence export guide with interactive, service principal, zone filter, and baseline inclusion examples
- `docs/TROUBLESHOOTING.md` — Comprehensive troubleshooting guide covering deployment, authentication, validation, drift detection, evidence export, and Power Automate flow issues
- Updated `docs/PREREQUISITES.md` with MSAL.PS module requirement for evidence export

### Changed
- README.md updated to v1.0.0 with evidence export features, Quick Start steps 5-6, expanded solution components tree, and documentation links section

## [0.3.0] - 2026-02-10

### Added
- Start-ModerationValidationRunbook.ps1 — Azure Automation runbook wrapper for non-interactive daily content moderation validation with certificate-based auth, per-agent drift detection via batch baseline query, and structured JSON output
- Invoke-ModerationBaselineCapture.ps1 — Operator-initiated per-agent baseline capture writing moderation levels to Dataverse with active baseline management and zone/environment/agent filtering
- adaptive-card-moderation-alert.json — Teams adaptive card template for content moderation violation and drift alerts with per-agent severity classification and regulatory context
- moderation-validation-flow.json — Power Automate cloud flow for daily scheduled moderation validation, immutable Dataverse history persistence, and conditional Teams/email alerting (Critical→Teams+email, High→email)
- FLOW_SETUP.md — Step-by-step guide for flow import, variable configuration, connection reference binding, baseline capture workflow, and troubleshooting

### Changed
- Save-CMMBaseline in CMMClient.psm1 completed with active baseline deactivation before new baseline write (single active baseline per agent)
- Get-ModerationBaseline in CMMClient.psm1 enhanced with -AgentId and -ActiveOnly parameters for per-agent drift detection and batch baseline queries
- CMMClient.psm1 version bumped to 0.3.0

## [0.2.0] - 2026-02-10

### Added — Phase 2: Dataverse Infrastructure

#### Python Deployment Scripts
- **cmm_client.py** — CMMClient Dataverse Web API client with MSAL auth (interactive + service principal)
- **create_dataverse_schema.py** — Three-table schema deployment (ModerationBaseline, ModerationValidationHistory, ModerationViolation)
- **create_environment_variables.py** — Seven `fsi_CMM_*` operational parameters
- **create_connection_references.py** — Three Power Automate connection references (Dataverse, Office 365, Teams)
- **deploy.py** — Full deployment orchestrator with selective/dry-run modes (`--tables-only`, `--vars-only`, `--refs-only`)
- **requirements.txt** — Python dependencies (msal, requests)

#### Dataverse Integration in PowerShell
- `-DataverseToken` parameter on `Test-ContentModerationCompliance` for pre-obtained authentication tokens
- `-PersistResults` switch for writing validation results to Dataverse
- Operational parameter reading from `fsi_CMM_*` environment variables (GracePeriodHours, IncludeDrafts, IncludeSandbox)
- RunId correlation across validation history and violation records
- `EnvironmentId` added to `Compare-ModerationCompliance` output

### Changed
- `Test-ContentModerationCompliance` reads GracePeriodHours, IncludeDrafts, IncludeSandbox from Dataverse when connected
- Standalone mode (no `-DataverseUrl`) remains unchanged — no regression
- CMMClient.psm1 bumped to v0.2.0

## [0.1.0] - 2026-02-09

### Added — Phase 1 Plan 01-01: Solution scaffold and private helpers

#### Solution Structure
- Solution folder structure following Tier 2 pattern
- `moderation-baseline.json` — Zone-to-moderation-level requirements reference

#### Private Helpers
- **CMMClient.psm1** — Dataverse client module (10 exported functions)
  - `Connect-CMMDataverse`, `Get-CMMConnection` — Connection management
  - `Get-CMMEnvironmentVariable` — Environment variable lookup (`CMM_` prefix)
  - `Get-ModerationBaseline` — Queries `fsi_moderationbaselines` table
  - `Write-ModerationValidationHistory` — Writes to `fsi_moderationvalidationhistory`
  - `Write-ModerationViolation` — Writes to `fsi_moderationviolations`
  - `Get-AgentBots` — Queries `bot` table with pagination support
  - `Get-BotModerationLevel` — Extracts and normalizes moderation level from bot config
  - `Save-CMMBaseline`, `Get-CMMLastValidation` — Phase 3 stubs

- **Connect-EnvironmentDataverse.ps1** — Per-environment Dataverse authentication
  - Token caching per DataverseUrl
  - Service principal support (PSCredential)
  - Interactive fallback via Az.Accounts
  - Clear error messages with remediation guidance

- **Get-ZoneClassification.ps1** — Zone lookup (ELM → naming convention → Unknown)
- **Get-ExpectedModerationLevel.ps1** — Zone-to-moderation compliance check with severity
- **Test-ParameterValidation.ps1** — Parameter validators including `Test-ModerationLevel`

#### Stubs
- `Get-AgentModerationSettings.ps1` — Stub for Plan 01-02
- `Compare-ModerationCompliance.ps1` — Stub for Plan 01-02
- `Test-ContentModerationCompliance.ps1` — Stub for Plan 01-03

#### Documentation
- `README.md` — Solution overview with zone requirements and severity matrix
- `CHANGELOG.md` — This file
- `docs/PREREQUISITES.md` — Module and permission requirements
- `docs/SCHEMA.md` — Stub for Dataverse schema documentation
- `docs/EVIDENCE_EXPORT.md` — Stub for evidence export documentation
- `docs/TROUBLESHOOTING.md` — Stub for troubleshooting guide
