# Changelog

All notable changes to the Environment Lifecycle Management solution.

## [1.2.0] - 2026-04-17 — BREAKING

> **BREAKING CHANGE:** Schema, option-set values, and the cross-solution
> zone contract have all moved to canonical form. Pre-existing Dataverse
> environments **cannot** be upgraded in place via this script — see the
> "Migration" note below.

### Changed (BREAKING)

- **Option-set values** are now in the publisher-prefix range
  (`100000001+`) for all 8 ELM global option sets — `fsi_er_state`,
  `fsi_er_zone`, `fsi_er_environmenttype`, `fsi_er_region`,
  `fsi_er_datasensitivity`, `fsi_er_expectedusers`, `fsi_pl_action`,
  `fsi_pl_actortype`. Previously they used `1..N`. Any flow,
  Power Automate expression, view filter, or downstream solution
  reading legacy `1..N` values must update.
- **Zone labels** in `fsi_er_zone` are now `Zone1`, `Zone2`, `Zone3`
  (no spaces). The shared `scripts/shared/Get-ZoneClassification.ps1`
  helper and all consumers depend on this exact spelling.
- **Cross-solution zone contract** (single source of truth):
  - Entity set: `fsi_environmentrequests`
  - Filter column: `fsi_environmentid`
  - Returned column: `fsi_zone` (values `100000001`/`100000002`/`100000003`)
  - Returned labels: `Zone1`/`Zone2`/`Zone3`
- **Lookup columns** (`fsi_Requester`, `fsi_Approver`, and the
  `fsi_environmentrequest` lookup on ProvisioningLog) are now created
  via `OneToManyRelationshipMetadata` POSTed to
  `/RelationshipDefinitions`, not via the `/Attributes` endpoint —
  the previous direct-attribute approach was rejected by the
  Dataverse Web API.
- **Business rules** are no longer created via the Web API.
  `scripts/create_business_rules.py` is now a documentation
  generator that prints maker-portal authoring instructions for the
  three ELM rules. Earlier versions emitted legacy `<RuleDefinitions>`
  XAML and posted with `statecode=1` (Activated), both of which were
  rejected by current Dataverse. See `docs/business-rules.md`.

### Added

- `docs/business-rules.md` — manual maker-portal authoring procedure
  for the three ELM business rules, with the full condition / action
  spec for each.
- `README.md` and `docs/dataverse-schema.md` — new "Cross-Solution
  Contract" sections that document the zone-classification schema
  consumed by other FSI-AgentGov solutions.
- `docs/flow-configuration.md` — new "Flow 0: Intake Flow" section
  describing the Copilot Studio → Dataverse handoff, including
  enum translation for the friendly intake payload.
- `docs/flow-configuration.md` — explicit Microsoft Graph
  `Group.Read.All` application permission requirement for the
  service principal (used during security-group binding).
- `elm_client.create_relationship()` — new Web API helper for
  posting relationship metadata.
- `register_service_principal.py` — `--expiry-days` now defaults to
  `90` (was required); a single retried session is reused across
  Graph calls and `POST` is no longer in the retry list (avoids
  duplicate apps/secrets on transient 5xx).
- `validate_immutability.py` — verifies `IsAuditEnabled=True` on
  `fsi_provisioninglog` before reporting PASS, and resolves the
  numeric `ObjectTypeCode` for the audit query (the `audits` table
  expects an int, not a logical name string).
- `export_quarterly_evidence.py` — JSON output is now sorted with
  `sort_keys=True`, written as UTF-8 bytes (avoids Windows cp1252
  drift in the SHA-256 hash), and FetchXML adds the primary key as a
  tie-breaker `order` attribute. The manifest now includes a
  `previousManifestHash` chain for cross-quarter tamper-evidence.
- `verify_role_privileges.py` — composite `privilegedepthmask`
  bitmasks (e.g., `7` = User+BU+Deep) now reduce to the highest set
  bit, matching how the Dataverse role designer renders them.
- `create_field_security.py` — printed guidance now states clearly
  that field-security profiles are associated with **users/teams**,
  not security roles.
- All five DateTime columns (`fsi_RequestedOn`, `fsi_ApprovedOn`,
  `fsi_ProvisioningStarted`, `fsi_ProvisioningCompleted`,
  `fsi_Timestamp`) are now `DateTimeBehavior=TimeZoneIndependent` so
  exported audit data hashes deterministically across regions.
- Approver-only columns (`fsi_State`, `fsi_Approver`, `fsi_ApprovedOn`,
  `fsi_ApprovalComments`) are now `IsSecured=true` so the field
  security profile actually applies.
- All `fsi_provisioninglog` non-key columns are now
  `IsValidForUpdate=false`, hardening the append-only contract at the
  metadata layer (in addition to the role-level revoke).
- `fsi_provisioninglog` primary column (`fsi_name`) is now an
  AutoNumber (`PL-{SEQNUM:8}`).

### Fixed

- `scripts/shared/Get-ZoneClassification.ps1` — was querying the
  non-existent `fsi_environments` table with `fsi_environment_guid`
  and `fsi_zone_classification`. Now queries `fsi_environmentrequests`
  with `fsi_environmentid` / `fsi_zone`, maps `100000001..3` to
  `Zone1..3`, and emits `Write-Warning` on lookup failure.
- `docs/flow-configuration.md` Step 16 — `_fsi_requester_value` is a
  Dataverse lookup GUID, not a UPN. Step now resolves it through the
  Dataverse `Users` table to get a UPN before calling Office 365
  Users.
- `docs/flow-configuration.md` Step 9 — invalid Power Automate
  expression `@first(filter(<array>, <prop>, <var>))` replaced with
  the supported 2-argument signature
  `first(filter(<array>, equals(<prop>, <var>)))`.
- `create_views.py` FetchXML literals — bumped from `1..8` to
  `100000001..100000008` to match the new option-set values.
- `README.md` — removed the OCC 2011-12 mapping (model risk is the
  scope of the model-risk-management-automation solution); added an
  explicit SEC 17a-4(f) WORM caveat next to the SEC 17a record-
  preservation row; cited "FINRA Rule 4511(a)" with section.
- Removed the Control 2.3 (Change Management) claim — ELM provisions
  environments themselves, but release planning across them belongs
  to the pipeline-governance-cleanup solution.
- `docs/copilot-agent-setup.md` line 543 — `contoso.com` →
  `example.com` (RFC 2606).

### Migration

- This is a schema-breaking change. Tenants that already deployed
  ELM v1.1.x must:
  1. Export any in-flight `fsi_environmentrequest` data.
  2. Delete the v1.1.x tables and global option sets (or build the
     v1.2.0 schema in a fresh environment and migrate data).
  3. Re-run `python scripts/deploy.py` (or `create_dataverse_schema.py
     --output-docs`) on a clean target.
  4. Re-author the three business rules per `docs/business-rules.md`.
  5. Republish all four flows and re-run any downstream solutions
     that read `fsi_zone` / `fsi_environmentid` so they pick up the
     canonical contract.

### Notes

- This release closes the Council Review (April 2026) findings on
  ELM. See the council reports under
  `~/.copilot/session-state/.../files/elm/` for the full audit
  trail.
- The `dataverse_client.py`-shared-base refactor is **deferred** —
  ELM continues to ship its own `elm_client.py`. We will revisit
  consolidation in a future release.

---

## [1.1.3] - 2026-04-15

### Fixed

- Added missing --client-id to interactive deployment examples in README (required by DataverseClient)

## [1.1.2] - 2026-01-31

### Changed

- **Documentation Accuracy:** Corrected Environment Groups API claim in prerequisites.md (API exists via `POST .../environmentGroups`)
- **Security Dependencies:** Updated Python dependency versions for security and feature improvements:
  - `msal>=1.30.0` (token caching improvements)
  - `requests>=2.32.0` (CVE-2024-35195 security fix)
  - `azure-identity>=1.18.0` (CAE support)

### Notes

- Part of ELM Technical Accuracy Remediation (research validation: 71% accurate, 29% updated)
- See FSI-AgentGov v1.2.26 for related framework documentation updates

---

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
