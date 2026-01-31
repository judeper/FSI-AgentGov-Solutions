# Changelog

All notable changes to the Environment Lifecycle Management solution.

## [1.1.1] - 2026-01-31

### Changed

- **BREAKING:** `register_service_principal.py` now requires explicit `--expiry-days` (30-365 range)
- **BREAKING:** `elm_client.py` now requires explicit `--client-id` for all authentication modes
- `validate_immutability.py` exit codes: 2=integrity issues, 3=violations (was both 3)
- `create_security_roles.py` now returns success/failure status and exits with code 1 on failures
- `create_field_security.py` now returns success/failure status

### Added

- `deploy.py` pre-flight validation shows existing schema state in dry-run mode
- `export_quarterly_evidence.py` warns when exports contain 0 records
- `create_security_roles.py` tracks and reports failed privilege assignments
- `create_field_security.py` validates all fields exist before starting

### Fixed

- README.md Data Model section now uses correct `fsi_` prefix (was `er_`/`pl_`)
- README.md Prerequisites section now appears before Automated Deployment

---

## [1.1.0] - 2026-01-30

### Added

- **Automated Dataverse Deployment** - New `deploy.py` orchestrator for quick lab/dev setup
  - Creates all Dataverse components via Web API
  - Supports `--dry-run` for preview without changes
  - Supports `--interactive` for browser-based authentication
  - Supports `--tables-only` and `--roles-only` for selective deployment
- **Schema Automation Scripts:**
  - `create_dataverse_schema.py` - Creates tables, columns, and global option sets
  - `create_security_roles.py` - Creates 4 security roles with correct privileges
  - `create_business_rules.py` - Creates conditional required field rules
  - `create_views.py` - Creates 8 model-driven app views
  - `create_field_security.py` - Creates ELM Approver Fields profile
- **Enhanced elm_client.py:**
  - Added metadata operations for entity/attribute/optionset creation
  - Added interactive browser authentication support
  - Added methods for roles, privileges, views, workflows, field security

### Changed

- Updated README.md with automated deployment quick start section
- Updated SETUP_CHECKLIST.md with Option A (automated) path
- Updated Known Limitations table to reflect new automation capabilities

### Removed

- Removed unused `msgraph-sdk` dependency from requirements.txt

### Notes

- Automated deployment recommended for lab/dev environments
- Production deployment should use manual process for audit trail
- Copilot Studio agents and Power Automate flows still require manual creation

---

## [1.0.1] - 2026-01-29

### Fixed

- Added `--verbose` flag to `register_service_principal.py` for stack trace output on errors
  - Matches pattern used by other scripts (`export_quarterly_evidence.py`, `validate_immutability.py`)
  - Improves debugging for authentication and API errors

---

## [1.0.0] - 2026-01-29

### Added

- Initial release of Environment Lifecycle Management solution
- **Data Layer:**
  - EnvironmentRequest table schema (22 columns)
  - ProvisioningLog table schema (11 columns, immutable)
  - Four security roles (Requester, Approver, Admin, Auditor)
  - Business rules for conditional required fields
- **Python Scripts:**
  - `elm_client.py` - Dataverse Web API wrapper with MSAL authentication
  - `register_service_principal.py` - Entra app registration and Key Vault integration
  - `export_quarterly_evidence.py` - FetchXML-based evidence export with SHA-256 hashing
  - `verify_role_privileges.py` - Security role privilege audit
  - `validate_immutability.py` - ProvisioningLog immutability verification
- **Documentation:**
  - Complete Dataverse schema specification
  - Security role privilege matrix
  - Service Principal setup guide
  - Power Automate flow configuration
  - Copilot Studio agent topic definitions
  - Troubleshooting and error recovery guide
- **Templates:**
  - Sample EnvironmentRequest JSON
  - Copilot Studio JSON output schema

### Notes

- Copilot Studio agent must be created manually (no deployment API)
- Environment Groups must be created manually in PPAC
- Power Automate flows must be created manually or imported as solution
- Service Principal registration automated via Python script

### Related

- FSI-AgentGov Framework v1.2.10
- [Environment Lifecycle Management Playbook](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/environment-lifecycle-management/index.md)
