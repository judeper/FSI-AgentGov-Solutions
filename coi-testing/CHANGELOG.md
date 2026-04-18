# Changelog

All notable changes to the COI Testing Framework.

---

## [1.1.0] - 2026-04-30

### Fixed

- **Critical**: `fsi_status` is a Dataverse Choice column and requires option-set values in the `100000000+` range; the previous mapping (`PASS=1`, `FAIL=2`, ...) caused every Web API write to fail with `BadRequest`. Status values now correctly map PASS=`100000000`, FAIL=`100000001`, SKIPPED=`100000002`, WARN=`100000003`, ERROR=`100000004` and are documented in the new `docs/dataverse-schema.md`.
- **Critical**: The runner returned exit code `0` even when zero scenarios executed or every scenario reported `SKIPPED`, which made schedulers and CI treat a non-test as a passing control evidence run. The runner now exits `2` when nothing executed and exits `3` when everything was skipped (overridable with the new `--allow-skipped` flag for intentional scaffold smoke-tests).
- **High**: Quick Start documented a `config.py` with `direct_line_secret` / `agent_id` that the runner never reads — following the documented setup could not connect any agent. Replaced with the credentials the runner actually consumes (`AZURE_TENANT_ID`/`AZURE_CLIENT_ID`/`AZURE_CLIENT_SECRET`).
- **High**: README claimed 3 fee-transparency scenarios, 3 cross-selling scenarios, and a "weekly 20+ scenarios" suite. Only 10 scenarios exist (3 PB, 3 SU, 2 FT, 2 CS). Removed the ghost scenarios and the inaccurate scheduled-runner table; added an *Implementation Status* matrix that honestly states which components exist.
- **High**: README claimed automatic FINRA Supervision and Compliance Dashboard integration; neither is implemented. Re-labelled both as planned integrations.
- **Medium**: `--report json` and `--report html` previously emitted progress banners on stdout, breaking JSON pipes. All progress / banner / per-scenario lines now go to `stderr`; the report itself is the only thing on stdout.
- **Medium**: Replaced `datetime.utcnow()` (deprecated and warning-noisy on Python 3.12+) with `datetime.now(timezone.utc)`.
- **Medium**: Added `docs/dataverse-schema.md` so the `fsi_coitestresult` table can actually be created from this folder.
- **Medium**: Solution README now uses "Microsoft Entra ID app registration" instead of an "Agent Reader" role that does not correspond to a real Power Platform / Dataverse role.
- **Low**: Stale `Expected in v1.0.0` reference in troubleshooting replaced with version-neutral wording.
- **Low**: Removed committed `__pycache__/run_coi_tests.cpython-312.pyc`.

### Known Limitations

- Direct Line agent invocation and pass/fail evaluation are not yet implemented; every scenario reports `SKIPPED` until that integration ships. This is now documented up-front and gated by the new `--allow-skipped` exit code.

---

## [1.0.2] - 2026-04-15

### Fixed

- Status persistence now correctly maps SKIPPED/WARN/ERROR to distinct Dataverse values (was coercing all non-PASS to FAIL)
- Added SKIPPED count to test report generation
- Updated README version footer to match current version

---

## [1.0.1] - April 2026

### Added

- Documentation suite: docs/prerequisites.md, docs/test-scenarios.md, docs/troubleshooting.md

---

## [1.0.0] - 2026-02-15

### Added

- Initial release of COI Testing Framework
- **Test Categories:**
  - Proprietary product bias detection (3 scenarios)
  - Suitability testing (3 scenarios)
  - Fee transparency verification (2 scenarios)
  - Cross-selling analysis (2 scenarios)
- **Python Test Runner:**
  - `run_coi_tests.py` - Execute tests against agents
  - Scheduled and on-demand execution
  - Text, JSON, HTML report formats
- **Dataverse Integration:**
  - Test result storage
  - Finding tracking
  - Supervision workflow integration
- **Documentation:**
  - Test scenario library
  - Custom test creation guide

### Regulatory Alignment

- FINRA Rule 2111 - Suitability
- FINRA Rule 2010 - Standards of Commercial Honor
- FINRA Rule 2210 - Communications
- SEC Regulation Best Interest

---

*COI Testing Framework - FSI Agent Governance Framework*
