# Changelog

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

- [FLOW_SETUP.md](./FLOW_SETUP.md) - Complete Power Automate flow documentation
- [TEAMS_INTEGRATION.md](./TEAMS_INTEGRATION.md) - Teams notification setup guide
- [SECRETS_MANAGEMENT.md](./SECRETS_MANAGEMENT.md) - Azure Key Vault configuration
- [SETUP_CHECKLIST.md](./SETUP_CHECKLIST.md) - Quick 10-step deployment checklist
- [teams-notification-card.json](./teams-notification-card.json) - Adaptive card template

### Changed

- Solution folder renamed: `platform-change-governance/` → `message-center-monitor/`
- Single-table data model with assessment fields built-in
- Documentation rewritten for operational monitoring focus
- Simplified prerequisites (no Python, no System Administrator role)

---

## [1.3.0] - January 2026

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

## [1.2.0] - January 2026

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

## [1.1.0] - January 2026

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

## [1.0.0] - January 2026

### Initial Release

- MessageCenterPost, AssessmentLog, DecisionLog tables
- 4 security roles
- Model-driven app
- Business Process Flow
