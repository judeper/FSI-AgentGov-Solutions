# Changelog

## [2.3.0] - 2026-04-17

### Fixed
- **High:** README Step 1 "Quick Start" walked admins through manually creating a `MessageCenterLog` table with a tenant-default publisher prefix (e.g., `cr123_`). The shipped PowerShell governance scripts hardcode the `fsi_` prefix, so manual deployments would 404 on every Sync/Status/Export operation. README Step 1 now points to `python scripts/create_mcm_dataverse_schema.py` as the canonical deployment path and explicitly states that an alternate prefix is unsupported.
- **High:** Flow-configuration Switch examples mapped Microsoft Graph category/severity enums to text labels (`Feature`, `High`) instead of the option-set integer values (`100000000`/`100000001`/`100000002`) defined in the schema. Power Automate would have failed at the Update Row step. Switch cases now use the canonical option-set integers and reference the schema source of truth.
- **High:** Dataverse application-user prerequisite was missing from the README. The PowerShell governance scripts call the Dataverse Web API as the same Entra app used for Microsoft Graph and would 401/403 without a Dataverse app user. README "Prerequisites" now includes a dedicated "Dataverse Application User" step covering app-user creation and security-role assignment.
- **High:** All `cr123_` placeholder publisher-prefix references across `README.md`, `docs/flow-configuration.md`, `docs/teams-integration.md`, and `docs/setup-checklist.md` normalized to the canonical `fsi_` prefix that matches the schema script and governance scripts.
- **High:** Logical name `cr123_messagecenterId` (uppercase `Id`) corrected to `cr123_messagecenterid` across docs — Dataverse logical names are always all-lowercase and never insert underscores between words.

### Changed
- **Medium:** `Invoke-MessageCenterSync.ps1` now uses an `Invoke-MCMRest` helper that honors `Retry-After` for HTTP `429`/`503` responses with exponential-backoff fallback (max 5 retries). Previously, a single Graph or Dataverse throttling response aborted the entire sync.
- **Medium:** `Invoke-MessageCenterSync.ps1` now tracks per-record persistence failures (`FailedRecords` count + `FailedMessageIds` list) and exits non-zero when any Dataverse operation fails. Previously, partial failures were logged as warnings and the script exited 0, hiding silent data loss from scheduled runs (Azure Automation, Logic Apps, GitHub Actions).
- **Medium:** `Invoke-MessageCenterSync.ps1` truncates `fsi_body` to 99,990 characters with a `[truncated — original length N chars]` marker when an inbound Microsoft 365 Message Center HTML body exceeds the column's MaxLength. Previously, oversized bodies failed the upsert silently.
- **Medium:** `Get-MessageCenterAssessmentStatus.ps1` now defaults `TenantId`/`ClientId` to `$env:AZURE_TENANT_ID`/`$env:AZURE_CLIENT_ID` (matching the Sync script) and validates them before MSAL calls so missing values produce a clear error rather than an opaque MSAL exception.
- **Low:** Regulatory citations in `Export-MessageCenterEvidence.ps1` and `Test-EvidenceIntegrity.ps1` updated to canonical forms (`FINRA Rule 4511(a)`, `SOX Section 302 / SOX Section 404`).

## [2.2.0] - 2026-04-10

### Added
- Dataverse schema script with 1 table, 3 option sets, and `--output-docs` support
- Environment variables script (6 variables for polling, notifications, Teams, Key Vault)
- Connection references script (Dataverse, Teams, Key Vault, HTTP Premium)
- PowerShell governance scripts: Invoke-MessageCenterSync, Get-MessageCenterAssessmentStatus, Export-MessageCenterEvidence, Test-EvidenceIntegrity
- Auto-generated Dataverse schema documentation
- Python requirements.txt

## [2.1.3] - 2026-04-10

### Changed

- Restructured solution to follow standard layout
- Moved documentation from root to `docs/` folder (flow-configuration, secrets-management, setup-checklist, teams-integration)
- Moved Teams notification card template to `templates/`
- Removed `src/` directory (per solution content policy)

---

## [2.1.2] - 2026-03-15

### Correctness Fixes

**Pagination Array Bug (CRITICAL):**
- Replaced `Append to array` with `Set variable` + `union()` in pagination pattern (FLOW_SETUP.md)
- `Append to array` creates nested arrays `[[page1], [page2]]` instead of a flat message list
- Added warning callout explaining why `Append to array` must not be used here

**Missing Critical Severity in Notification Conditions (HIGH):**
- Added `critical` severity check to all three notification condition variants
- Previously only `high` was checked; `critical` posts would silently skip notification
- Added `critical` case to severity Switch mapping

**Flow Diagram Contradicted Error Handling Guidance (MEDIUM):**
- Moved `Apply to each` inside the Try scope in the Complete Flow Structure diagram
- Updated mini pagination diagram to use `Set` instead of `Append`

**Missing recordId Placeholder Documentation (MEDIUM):**
- Added `{recordId}` to the placeholder replacement table in Step 7

**SETUP_CHECKLIST.md Terminology (LOW):**
- Updated Step 1 from Azure AD to Microsoft Entra ID
- Fixed broken anchor link to README.md

#### Files Modified

| File | Changes |
|------|---------|
| FLOW_SETUP.md | Pagination fix, critical severity, diagram fix, recordId placeholder |
| SETUP_CHECKLIST.md | Entra ID terminology, fixed anchor link |
| CHANGELOG.md | Added v2.1.2 entry |

---

## [2.1.1] - 2026-01-15

### Technical Accuracy Updates

This release addresses terminology and deprecation updates identified during technical validation against official Microsoft documentation.

#### Terminology Updates

**Azure AD → Microsoft Entra ID:**
- Updated all documentation to use "Microsoft Entra ID" (rebranded in 2023)
- Updated portal navigation instructions to reference Microsoft Entra admin center
- Files affected: README.md, FLOW_SETUP.md, SECRETS_MANAGEMENT.md

**Admin Consent Clarification:**
- Changed "requires Global Admin" to "requires an administrator with permission to consent"
- Admin consent can be granted by any admin with enterprise application consent permissions, not exclusively Global Admins

#### Teams Connector Updates

**Action Name Changes:**
- Updated action name from "Post adaptive card in a chat or channel" to "Post card in a chat or channel"
- Added note that existing flows with old action name will continue to work
- Added Adaptive Card version compatibility note (Teams supports versions 1.0-1.5)

#### API Documentation Enhancements

**Page Size Documentation:**
- Added note that maximum page size is 1000 (via `Prefer: odata.maxpagesize=1000` header)
- Default page size remains 100 items

#### Files Modified

| File | Changes |
|------|---------|
| README.md | Entra ID terminology, admin consent clarification, version bump |
| FLOW_SETUP.md | Entra ID terminology, Teams action update, max page size note |
| TEAMS_INTEGRATION.md | Teams action name update, Adaptive Card version compatibility |
| SECRETS_MANAGEMENT.md | Entra ID terminology (all Azure AD references) |

---

## [2.1.0] - 2026-01-15

### Technical Review Fixes

This release addresses 12 issues identified during technical review of the documentation.

#### Critical Fixes

**API Value Corrections:**
- Fixed category mapping typo: `preventOrFixIssues` → `preventOrFixIssue` (FLOW_SETUP.md)
- Added "Critical" severity option to match Microsoft Graph API values (README.md, SETUP_CHECKLIST.md)

**Notification Logic:**
- Updated notification condition to include both `high` and `critical` severity levels (FLOW_SETUP.md)

**Implementation Guidance:**
- Added step-by-step alternate key creation instructions for Dataverse upsert (FLOW_SETUP.md)

#### Schema Improvements

**Missing Fields Added:**
- `lastModifiedDateTime` (DateTime) - When Microsoft last updated the post
- `isMajorChange` (Yes/No) - Microsoft's flag for significant changes

These fields were already in the sample JSON but missing from the table schema documentation.

**Sample JSON Updated:**
- Added `@odata.nextLink` pagination field with explanatory note

#### Documentation Clarifications

**New Sections Added:**
- Choice field implementation guide with Switch action examples (FLOW_SETUP.md)
- Publisher prefix discovery instructions - 3 methods to find your prefix (TEAMS_INTEGRATION.md)
- Flow identity explanation - user-based vs service principal flows (SECRETS_MANAGEMENT.md)
- Naming convention note - display names vs logical names (README.md)

**Improved Guidance:**
- Expanded error handling scope to include Apply to each loop in Try scope
- Added null handling for body content using `coalesce()` expression
- Added choice values table to setup checklist

#### Files Modified

| File | Changes |
|------|---------|
| README.md | Added Critical severity, missing schema fields, naming note |
| FLOW_SETUP.md | Fixed typo, updated conditions, added implementation guidance |
| TEAMS_INTEGRATION.md | Added publisher prefix discovery instructions |
| SECRETS_MANAGEMENT.md | Added flow identity explanation |
| SETUP_CHECKLIST.md | Added severity choice values, missing fields |

---

## [2.0.0] - January 2025

### Breaking Changes

**Complete Architecture Simplification:**

This release fundamentally changes the solution from a compliance-focused governance system to an operational monitoring tool.

**What Changed:**

| Before (v1.x) | After (v2.0.0) |
|---------------|----------------|
| 3 tables (MessageCenterPost, AssessmentLog, DecisionLog) | 1 table (MessageCenterLog) |
| 4 custom security roles | Standard Dataverse permissions |
| Python deployment script (2100+ lines) | Power Automate flow (manual setup) |
| Business Process Flow (5 stages) | Simple status field |
| SOX/FINRA/SEC compliance claims | Operational monitoring only |
| Folder: `platform-change-governance/` | Folder: `message-center-monitor/` |

**Why This Change:**

- External review identified the solution as over-engineered for its actual use case
- Message Center logs are operational information, not regulatory compliance evidence
- SOX, FINRA, and SEC do not require tracking of Microsoft platform announcements
- Simplified design is easier to deploy, maintain, and customize

**Migration:**

If you deployed v1.x, there is no automatic migration. Options:

1. **Keep v1.x** - Your existing deployment continues to work
2. **Start fresh with v2.0.0** - Deploy the new simplified solution alongside
3. **Manual migration** - Export data from old tables, import to new single table

### Removed

- `deploy_mcg.py` - Python deployment script (2100+ lines)
- `requirements.txt` - Python dependencies
- AssessmentLog table - Merged into main table
- DecisionLog table - Merged into main table
- 4 custom security roles (MC Admin, MC Owner, MC Compliance Reviewer, MC Auditor)
- Business Process Flow
- Model-driven app
- Compliance Notice section in documentation
- All SOX/FINRA/SEC regulatory references

### Added

- [docs/flow-configuration.md](docs/flow-configuration.md) - Complete Power Automate flow documentation
- [docs/teams-integration.md](docs/teams-integration.md) - Teams notification setup guide
- [docs/secrets-management.md](docs/secrets-management.md) - Azure Key Vault configuration
- [docs/setup-checklist.md](docs/setup-checklist.md) - Quick 10-step deployment checklist
- [templates/teams-notification-card.json](templates/teams-notification-card.json) - Adaptive card template

### Changed

- Solution folder renamed: `platform-change-governance/` → `message-center-monitor/`
- Single-table data model with assessment fields built-in
- Documentation rewritten for operational monitoring focus
- Simplified prerequisites (no Python, no System Administrator role)

---

## [1.3.0] - 2026-01-15

> **Note:** v1.3.0 was the final release of the compliance-focused design. See v2.0.0 for the simplified approach.

### Critical Fixes

**Privilege Propagation Timing (CRITICAL):**
- Replaced fixed 10-second sleep with polling loop that verifies privileges exist
- Added `wait_for_privileges()` method with configurable timeout (default: 120s)
- Prevents security roles from being created with ZERO privileges

**Silent Privilege Assignment Failures (CRITICAL):**
- `create_security_role()` now returns list of failed privilege assignments
- All failures are tracked and reported at end of deployment
- Deployment continues but clearly warns about incomplete role configurations

**Primary Name Truncation (CRITICAL):**
- Increased `mcg_Name` max_length from 100 to 300 characters for AssessmentLog and DecisionLog
- Prevents guaranteed truncation when auto-generating from 500-char titles

### Security Fixes

**Client Secret Handling (HIGH):**
- Client secret now read from `MCG_CLIENT_SECRET` environment variable (recommended)
- Falls back to `--client-secret` argument if env var not set
- Interactive prompt if neither provided

**DecisionLog Ownership Model (HIGH):**
- Changed from OrganizationOwned to UserOwned
- Enables proper `createdby`/`modifiedby` tracking

**Added mcg_DecidedBy Field (HIGH):**
- New required Lookup to SystemUser on DecisionLog
- Explicitly tracks WHO made each decision

**DecisionLog Immutability (HIGH):**
- Removed Write privilege from MC Compliance Reviewer for DecisionLog
- Decisions are now immutable once created (Create-only)

**MC Admin Cannot Delete Audit Records (HIGH):**
- Removed Delete privilege from MC Admin for DecisionLog

**Category/Severity Now Required (HIGH):**
- Changed RequiredLevel to ApplicationRequired for both fields
- These fields come from Microsoft and should always be populated

### Role Privilege Adjustments

**MC Owner Enhancements:**
- Added Delete privilege for MessageCenterPost and AssessmentLog (User level)
- Added Assign privilege for AssessmentLog and DecisionLog (User level)

**MC Compliance Reviewer Enhancements:**
- Added Append/AppendTo privileges for MessageCenterPost (BusinessUnit level)
- Added Append/AppendTo privileges for DecisionLog (User level)

### Enhancements

**Deployment Verification Step:**
- Added Step 19: Automatic verification of all deployment components
- Verifies tables, roles (with privilege counts), views, environment variables, app
- Reports any issues detected

**Environment Variable Naming:**
- Renamed `mcg_MCG_TenantId` to `mcg_TenantId`
- Renamed `mcg_MCG_PollingInterval` to `mcg_PollingInterval`

**Governance Completion Tracking:**
- Added `mcg_ClosedOn` DateTime field to MessageCenterPost
- Added `mcg_ClosedBy` Lookup to SystemUser on MessageCenterPost

---

## [1.2.0] - 2026-01-15

### AI-Readiness & Critical Fixes

**AI-Friendly Descriptions:**
- Added descriptions to all 3 tables explaining their purpose for AI agent reasoning
- Added descriptions to all 26 columns with AI guidance
- Descriptions include correlation hints

**Critical Fix - Security Role Privileges:**
- Fixed PRIVILEGE_DEPTH values
- Now uses correct Dataverse Web API string enum names

**Deployment Order Fix:**
- Reordered to 18-step sequence ensuring privileges exist before role creation

**New Capabilities:**
- Security roles automatically associated with model-driven app
- Basic User role associated for minimum Dataverse access

---

## [1.1.0] - 2026-01-15

### Expanded Deployment Script

The `deploy_mcg.py` script now creates the complete solution via Dataverse Web API.

New capabilities added:
- Environment Variables
- Security Roles
- Views
- Main Form
- Model-Driven App
- Business Process Flow

---

## [1.0.0] - 2026-01-15

### Initial Release

- MessageCenterPost, AssessmentLog, DecisionLog tables
- 4 security roles
- Model-driven app
- Business Process Flow
