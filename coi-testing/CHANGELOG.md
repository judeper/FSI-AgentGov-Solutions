# Changelog

All notable changes to the COI Testing Framework.

---

## [Unreleased]

### Fixed

- **Minor (docs)**: `Get-CoiInventory.ps1` comment-based help mislabeled the solution as "Center of Influence (CoI)" — a distinct financial-services networking/referral term — in its `.SYNOPSIS`, `.DESCRIPTION`, `.EXAMPLE`, and run-summary banner. This solution is **Conflict of Interest (COI)** testing (manifest name, control 2.18). Corrected all four occurrences to "Conflict of Interest (COI)" / "COI" for internal consistency with the rest of the solution. `scripts/Get-CoiInventory.ps1:5,9,38,248`. (technical accuracy review vs Microsoft Learn)
- **Docs**: Repaired a truncated/orphaned note blockquote at the top of `README.md` whose lead-in clause had been lost (it began mid-sentence with "> implemented; the agent-interaction layer..."). Reconstructed it into a complete scaffold-status note consistent with the *Overview* and *Implementation Status* sections. (lab-readiness validation)
- **Minor**: `Get-CoiInventory.ps1` no longer passes `--json` to `pac connection list`. Unlike `pac admin list` and `pac solution list`, the `pac connection list` command does not support a `--json` flag (only `--environment`), so the unknown option would cause PAC to error and the connection enumeration to return empty. `Invoke-PacCommand` already falls back to capturing the tabular text output when JSON is unavailable. `scripts/Get-CoiInventory.ps1:227`. (second-pass command-existence audit)

## [1.1.2] - 2026-05-23

### Fixed

- **Major**: Hardened `generate_report()` pass-rate calculation against external callers invoking it on an empty runner. The denominator is now guarded by `total > 0` (where `total = len(self.results)`) extracted into a local variable before division, and the result is stored in `pass_rate` rather than computed inline. `scripts/run_coi_tests.py:492`. (council review M-1)
- **Minor**: HTML report generator now applies `html.escape()` to `scenario_id`, `scenario_name`, `status`, `finra_rule`, and the execution timestamp before f-string interpolation. Defense-in-depth against custom scenarios whose names could contain `<`, `>`, or `&`. `scripts/run_coi_tests.py:492`. (council review m-3)
- **Minor**: ANSI color escape sequences in per-scenario status output are now suppressed when `sys.stderr` is not a TTY. Eliminates color noise in log-file captures. `scripts/run_coi_tests.py:430`. (council review m-7)

### Changed

- **Minor**: Renamed the `generate_report(format=...)` parameter to `report_format` to avoid shadowing the Python built-in `format()` (ruff A002). Existing positional call sites are unaffected. `scripts/run_coi_tests.py:492`. (council review m-1)
- **Minor**: `Invoke-PacCommand` in `Get-CoiInventory.ps1` now accepts the PAC CLI argument list as a `[string[]]` array and splats it with `& pac @Command` instead of splitting a single string on space. Future arguments that contain whitespace are now passed through verbatim. All three call sites updated to the array form. `scripts/Get-CoiInventory.ps1:94`. (council review m-2 — note: the council report cited `scripts/run_coi_tests.py:117`, which was a file-name transposition; the actual defect was in `Get-CoiInventory.ps1`.)
- **Minor**: Clarified `docs/dataverse-schema.md` shared-client reference. The shared library can be used to script table creation programmatically, but no turnkey `create_coi_dataverse_schema.py` generator exists in this solution. (council review m-4)
- **Minor**: Tightened `manifest.yaml` verification statement to call out that `--dry-run` intentionally skips Dataverse persistence; persistence verification requires running without `--dry-run`. (council review m-5)
- **Minor**: Annotated v1.0.0 changelog entry below to flag the aspirational items that were corrected in v1.1.0 (council review m-6).
- **Minor**: Updated `docs/troubleshooting.md` to reflect the M-1 and m-7 fixes shipped in this release.

### Notes

No false positives. All eight findings (1 Major, 7 Minor) verified against the live tree at base commit `1ef88bb` before fixing. No critical findings were raised by the council.

The council report's m-2 entry mis-cited `scripts/run_coi_tests.py:117`; the live defect was `scripts/Get-CoiInventory.ps1:117`. Fix applied to the actual location.

---

## [1.1.1] - 2026-05-17

### Changed

- Refreshed Dataverse authentication guidance and runner support for managed identity, workload identity federation, certificate auth, Azure CLI auth, and legacy development client-secret fallback based on Microsoft Learn 2026-Q2 guidance.
- Updated COI scaffold documentation for current Dataverse option-set values, Direct Line/OAuthCard caveats, Copilot Studio Kit testing alignment, and FINRA citation scope.

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

> **Historical note (added in v1.1.2):** Several "Added" bullets below describe
> aspirational features that did not ship in v1.0.0 — specifically *Scheduled
> and on-demand execution*, *Finding tracking*, and *Supervision workflow
> integration*. These were corrected in v1.1.0 (see the v1.1.0 *Fixed* block
> above for the accurate status). The entry is preserved verbatim for audit
> traceability; treat the "Added" list as the original release notes, not as
> the actual implemented surface.

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
