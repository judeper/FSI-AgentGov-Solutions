# Changelog

## [1.3.0] - January 2026

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

### Security & Compliance Fixes

**Client Secret Handling (HIGH):**
- Client secret now read from `MCG_CLIENT_SECRET` environment variable (recommended)
- Falls back to `--client-secret` argument if env var not set
- Interactive prompt if neither provided
- Updated documentation with security warnings

**DecisionLog Ownership Model (HIGH):**
- Changed from OrganizationOwned to UserOwned
- Enables proper `createdby`/`modifiedby` tracking for compliance audit

**Added mcg_DecidedBy Field (HIGH):**
- New required Lookup to SystemUser on DecisionLog
- Explicitly tracks WHO made each governance decision
- Required for SOX/FINRA compliance

**DecisionLog Immutability (HIGH):**
- Removed Write privilege from MC Compliance Reviewer for DecisionLog
- Decisions are now immutable once created (Create-only)

**MC Admin Cannot Delete Audit Records (HIGH):**
- Removed Delete privilege from MC Admin for DecisionLog
- Audit records preserved for compliance

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
- Warns if any security role has ZERO privileges

**Environment Variable Naming:**
- Renamed `mcg_MCG_TenantId` to `mcg_TenantId` (removed redundant prefix)
- Renamed `mcg_MCG_PollingInterval` to `mcg_PollingInterval`

**Governance Completion Tracking:**
- Added `mcg_ClosedOn` DateTime field to MessageCenterPost
- Added `mcg_ClosedBy` Lookup to SystemUser on MessageCenterPost

**Lookup Column Support:**
- Added `add_lookup_column()` method for creating lookups to system entities
- Used for mcg_DecidedBy and mcg_ClosedBy fields

### Documentation

**README Updates:**
- Added Python 3.10+ requirement
- Added security warning about command-line secrets
- Clarified two separate app registrations requirement
- Updated environment variable examples
- Updated version to 1.3.0

**Deployment Output:**
- Version bumped to 1.3.0 in deployment script banner
- 19-step deployment sequence (was 18)
- Verification report at end of deployment

---

## [1.2.0] - January 2026

### AI-Readiness & Critical Fixes

**AI-Friendly Descriptions:**
- Added descriptions to all 3 tables explaining their purpose for AI agent reasoning
- Added descriptions to all 26 columns with AI guidance (including choice value semantics)
- Descriptions include correlation hints (e.g., "correlate Severity with ActionRequiredBy date")
- Choice values embedded in column descriptions since OptionSet descriptions aren't supported via API

**Critical Fix - Security Role Privileges:**
- Fixed PRIVILEGE_DEPTH values (were off by 1 AND using wrong format)
- Now uses correct Dataverse Web API string enum names: "Basic", "Local", "Deep", "Global"
- Added warning logging when privilege assignment fails

**Deployment Order Fix:**
- Reordered to 18-step sequence ensuring privileges exist before role creation
- Views, Forms, BPF created before first publish
- Security Roles created after first publish (privileges now available)
- Added 10-second wait after publish for privilege propagation

**New Capabilities:**
- Security roles automatically associated with model-driven app
- Basic User role associated for minimum Dataverse access
- Views, forms, and BPF added as explicit app components
- FormXML fix: Changed `<ViewIds>` to `<ViewId>` (singular) for subgrids

**Documentation:**
- Prerequisites updated: System Administrator required (not System Customizer)
- Expanded manual steps with full Azure AD OAuth configuration
- Detailed Power Automate flow creation guide with HTTP connector auth
- BPF portal configuration instructions

**Remaining Manual Steps (2):**
1. Azure AD app registration with ServiceMessage.Read.All (Application permission) + admin consent
2. Power Automate flow for Message Center ingestion + BPF activation

---

## [1.1.0] - January 2026

### Expanded Deployment Script

**Automated Component Creation:**

The `deploy_mcg.py` script now creates the **complete solution** via Dataverse Web API, reducing manual steps from 7 to 2.

New capabilities added:
- **Environment Variables:** MCG_TenantId (String), MCG_PollingInterval (Number, default: 21600)
- **Security Roles:** MC Admin, MC Owner, MC Compliance Reviewer, MC Auditor with appropriate privileges
- **Views:** All Open Posts (default), New Posts - Awaiting Triage, High Severity Posts, My Assigned Posts
- **Main Form:** 5-tab layout (Overview, Content, Assessment, Decision, Audit Trail) with subgrids
- **Model-Driven App:** Message Center Governance with sitemap and entity components
- **Business Process Flow:** 5-stage governance workflow (New → Triage → Assess → Decide → Closed)

**Remaining Manual Steps:**

After running the script, only these steps remain:
1. Create Azure AD app registration with `ServiceMessage.Read.All` permission
2. Create Power Automate flow for Message Center ingestion

**Script Improvements:**
- 15-step deployment process (up from 9)
- Idempotent: safe to run multiple times without duplicate creation
- Progress indicators for each component type
- Graceful handling of API limitations for BPF creation

---

## [1.0.0] - January 2026

### Initial Release

**Solution Components:**

- MessageCenterPost, AssessmentLog, DecisionLog tables
- 4 security roles (MC Admin, MC Owner, MC Compliance Reviewer, MC Auditor)
- Model-driven app with forms, views, and dashboard
- Business Process Flow (New → Triage → Assess → Decide → Closed)
- Environment variables: MCG_TenantId, MCG_PollingInterval (default: 6 hours)

**Repository Structure:**

- Unmanaged solution .zip for portal import
- Unpacked src/ folder for version control and customization
- Comprehensive README with prerequisites (DLP, Solution Checker)

### Prerequisites

Before importing, verify:

- DLP policy allows HTTP connector to graph.microsoft.com
- Solution Checker enforcement mode (if Managed Environment)
- Required permissions (Environment Maker, Application Administrator)

### Documentation

Full documentation available in FSI-AgentGov:

- [Platform Change Governance Playbook](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/platform-change-governance/index.md)
