# Changelog

All notable changes to FSI-AgentGov-Solutions are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased] - 2026-Q3 — 43-solution review (issue #205)

### Fixed
- **Partial control coverage no longer silently upgraded to full.** Six solutions (`action-confirmation-auditor`, `agent-access-monitor`, `agent-sharing-access-restriction-detector`, `content-moderation-monitor`, `file-upload-security`, `generative-ai-config-auditor`) carried hand-edited `coverage: "partial"` values in their **generated** `controls-covered.json`, while their `manifest.yaml` declared no partial coverage. Any run of `scripts/build-manifest.py` rewrote all 12 control claims across those six solutions to `coverage: "full"` and deleted the supporting gap notes — overstating compliance coverage in an artifact consumed by the framework `solutions-lock.json` contract. Each manifest now declares `controls_partial`, so the partial claims survive regeneration. The narrative evidence remains in each solution's `LAB-VALIDATION.md` (all six anchors verified to resolve).
- **`controls-covered.json` files now satisfy their own schema.** The hand-edited `coverageScope`/`notes` keys violated `scripts/controls-covered.schema.json` (`additionalProperties: false`) — 17 schema errors across the six files, now zero.
- **`manifest-check` could not detect committed-artifact drift.** The workflow ran `build-manifest.py` (which overwrites the committed artifacts on disk) *before* `build-manifest.py --check`, and `--check` compares generated content against the files on disk. The gate therefore compared generator output to itself and passed unconditionally on any committed drift, despite the step being named "…and committed artifacts are in sync". `--check` now runs first against the committed tree, generation follows, a second `--check` still proves determinism, and `git diff --exit-code` confirms generation left tracked files untouched.
- Resolved 4 unused-import (F401) lint findings in per-solution `tests/` directories.

### Added
- `manifest.yaml.controls_partial` is now documented in `scripts/manifest.schema.json`. The field was already read by `build-manifest.py` and used by two manifests, but was undocumented — which is why authors edited the generated file instead.
- `build-manifest.py` now fails validation when a `controls_partial` entry is absent from `controls[]`, instead of silently discarding the partial claim.
- `scripts/tests/test_build_manifest_partial_controls.py` — regression tests pinning partial-coverage round-tripping, manifest-as-source-of-truth, the subset guard, and schema conformance of the generated exports.

### Changed
- CI ruff scope widened from `scripts */scripts` to the whole repository. The previous globs skipped per-solution `tests/` directories, where the 4 findings above had accumulated unreported.
- Solution descriptions that hardcoded a framework control count are now count-neutral, so a future framework release cannot silently re-introduce control-count drift into the published catalog.

### Notes
- **The 79-versus-78 control count was investigated and deliberately left at 78.** Control 2.27 (Consumption-Entitlement Governance) exists only on the FSI-AgentGov `main` branch; it is absent from every released framework tag (v1.4.0, v1.5.0, v1.6.0, v1.6.1, v1.6.2 — all 78 controls). This repository pins a released framework tag by design (`FRAMEWORK_REF`, "Do NOT use 'main'"), so 78 is the correct baseline here until a framework release ships 2.27. Reconciling to 79 now would have published a control count no released framework version has.
- No new solutions were invented for the 38 orphan controls; they are reported as prioritised gaps.

---

## [Unreleased] - 2026-Q3 — Lab harness foundation

### Added
- Added `lab-harness/` one-time shared foundation for typed validation planning, runtime orchestration, Playwright portal smoke scaffolding, and evidence redaction/manifest tooling.
- Added schemas and templates for plan validation (`solution-validation-plan.schema.json`), ownership/cleanup (`ownership-cleanup.schema.json`), and summary metadata (`evidence-summary.schema.json`) plus static `audit-compliance-manager` PlanOnly example manifests.
- Added isolated Playwright package (`lab-harness/playwright`) with pinned dependencies, environment-driven `storageState`, fail-fast auth/account-picker helpers, and Node-based unit tests for config/helper behavior.
- Added Pester tests for path confinement, adapter allow-list enforcement, PlanOnly semantics, redaction coverage, manifest hashing, and gitignore protections.
- Added GitHub-hosted-only CI workflow `.github/workflows/lab-harness-ci.yml` scoped to harness files with no secret usage.

### Changed
- Hardened root `.gitignore` for lab harness auth state, transient Playwright outputs, and local evidence artifact folders while preserving tracked templates/schemas.

### Notes
- This foundation is public code only and does not provision tenant resources by itself.
- Live `workflow_dispatch` and persistent self-hosted runner execution remain in private follow-up work under `judep_microsoft/FSI-AgentGov-Lab`.

---

## [v1.7.2] - 2026-Q3 — CI fix (no functional change)

Patch release ensuring the Release pipeline (CycloneDX SBOM + Sigstore signing + Dataverse plugin DLL) ships with the v1.7.0 H-item wave content. Tag v1.7.0 and v1.7.1 are unchanged but their Release pipeline runs failed with `MSB1008: Only one project can be specified` due to Git Bash on Windows runners stripping the leading `/` from `/p:TreatWarningsAsErrors=true` (MSYS path conversion). v1.7.2 ships the same content as v1.7.1 plus the workflow fix (`-p:` form), so the Release pipeline now succeeds and attaches signed plugin + SBOM artifacts.

- **Fixed:** `.github/workflows/release.yml` — `dotnet build` now uses `-p:TreatWarningsAsErrors=true` (POSIX-style flag, not subject to MSYS path conversion). `ci-dotnet.yml` is unaffected because it uses PowerShell (backtick line continuations).

No solution code changes since v1.7.1.

---

## [v1.7.0] - 2026-05-12 — H-item adoption wave (5 domains, 35 H items)

Tracking summary: 6 triage aggregate issues #124, #125, #126, #127, #129, #130. This wave implements the **H-priority** consider-adopting items from each — shipping Microsoft Learn 2026-Q2 patterns as enforced code/schema across 22 solutions in 5 PRs. M-priority and Defer items remain in the aggregate issues for the next cycle.

### Added — content-data domain (PR #138, closes #125 H)
- **agent-knowledge-source-scanner**: Microsoft Graph v1.0 permissions scan path; JSON batching capped at 20 with `Retry-After` header handling and exponential backoff. (#125 H1+H2)
- **content-moderation-monitor**: Purview Audit / DSPM correlation — joins moderation events with Purview signals by user + timestamp + content hash. (#125 H3)
- **file-upload-security**: Downstream attachment validation examples (magic-number, Defender for Cloud, sensitivity label inheritance). (#125 H4)
- **rag-source-validator**: 5 new Dataverse columns for change detection and lineage — `fsi_etag`, `fsi_ctag`, `fsi_deltalink`, `fsi_searchconnectorid`, `fsi_lineageuri`. Additive schema migration. (#125 H5)
- **mime-type-restrictions**: WebP RIFF offset-8 `WEBP` signature validation (fixes RIFF/WAV collision). 32-test pytest suite covering WebP/TIFF/GIF/animated-GIF detection edge cases. (#125 H6+H8)
  - **Policy decision (H7):** REMOVED TIFF from Enterprise Managed default allowlist (multi-page documents + complex metadata = attack surface; not a Copilot Studio supported input type). KEPT non-animated GIF (low risk). FLAGGED animated GIF separately via `animatedGifPolicy: "flag-for-review"` config field, detected via NETSCAPE2.0 application extension marker.

### Added — lifecycle-ops domain (PR #137, closes #129 H)
- **coi-testing**: PAC CLI inventory script `Get-CoiInventory.ps1` enumerating CoI testing solutions, environments, and connections to gitignored `output/`. (#129 H1)
- **agent-365-lifecycle-governance**: Two new Dataverse environment variables — `fsi_ALG_DeletionHoldDays` (deletion grace period) and `fsi_ALG_AgentRegistryApiVersion` (Graph API version pinning). (#129 H2)
- **dr-testing-framework**: 3 KQL templates (DR scenario detection, replication lag, RPO/RTO measurement); emergency-access drill doc with OCC 2011-12 quarterly cadence and evidence collection format. (#129 H3+H4)
- **pipeline-governance-cleanup**: `Set-GovernanceConfig.ps1` wrapper for `pac admin set-governance-config` with verification; Manage pipelines walkthrough doc with structured screenshot placeholders. (#129 H5+H6)
- **message-center-monitor**: Service-health Graph ingestion (`ingest_service_health.py`) using `/admin/serviceAnnouncement/healthOverviews` and `/issues` endpoints; PowerShell `Invoke-MgGraphRequest` snippet doc. (#129 H7+H8)

### Added — agent-config domain (PR #139, closes #124 H)
- **agent-communication-restriction-detector**: Cross-tenant Entra correlation via Graph `crossTenantAccessPolicy`; child-agent input/output 1MB payload validation. (#124 H1+H2)
- **session-security-configurator**: Continuous Access Evaluation (CAE) configuration tracking per zone. (#124 H3)
- **credential-oversharing-detector**: Workload identity Conditional Access policy detection; cert/MI auth detection (flag client-secret as legacy); name-level OAuth scope baseline comparison. (#124 H4+H5+H6)
- **generative-ai-config-auditor**: Purview DLP / sensitivity label evidence collection. (#124 H7)
- **action-confirmation-auditor**: Azure Automation managed-identity runbook sample; Purview AI Hub / DSPM dual-confirmation evidence. (#124 H8+H9)

### Added — compliance-audit domain (PR #136, closes #126 H)
- **compliance-dashboard**: Full 78-control baseline dataset (16 missing controls added: 1.25–1.29, 2.22–2.26, 3.11–3.14, 4.8–4.9, sourced from `judeper/FSI-AgentGov` `CONTROL-INDEX.md`); `--output-docs` flag on `create_cd_dataverse_schema.py` for auto-generated schema docs (Council Review 2026-04-16 finding #1 mitigation). (#126 H1+H2)
- **audit-compliance-manager**: Validation tests asserting Dataverse logical names match the schema generator (no `_` between words). (#126 H3)
- **hitl-workflow-governance**: Anti-drift connector op-ID + option-set tests catching the 0/1/2/3 vs 100000000+ option-set mismatch pattern documented in Council Review. (#126 H4)
- **cross-solution-integration**: Dataverse alternate keys for upsert pattern (composite: `fsi_controlmasterid` + `fsi_assessmentdate` + `fsi_zone`). (#126 H5)
- **model-risk-management-automation**: Agent ID migration evidence section (SR 11-7 audit trail). (#126 H6)

### Added — access-identity domain (PR #135, closes #130 H)
- **cross-tenant-external-sharing-governance**: Two new Dataverse Memo columns on `fsi_EntraCTARecord` for `automaticUserConsentSettings` and `inboundTrust` CTA policy fields; `Scan-ManagedEnvBotSharingBaseline.ps1` scanner detecting deviations from recommended Managed Environment bot-sharing baseline. (#130 H1+H2)
- **unrestricted-agent-sharing-detector**: `Restore-AgentSharingFromEvidence.ps1` runbook restoring sharing relationships from evidence files via the `GrantAccess` Dataverse action; JSON audit trail. (#130 H3)
- **agent-sharing-access-restriction-detector**: Dynamic Entra group admission gate with `securityEnabled`/`mailEnabled` validation (rejects security-disabled and mail-enabled groups). New `SecurityEnabled`, `MailEnabled`, `GroupTypes` columns on `fsi_ApprovedSecurityGroupPolicy` for drift detection. (#130 H4)

### Skipped — monitoring-analytics domain (closes #127 H)
- After investigation, both H items in #127 were already implemented in their source PRs:
  - **H1** (dual-schema KQL `union isfuzzy=true`): already shipped in `copilot-studio-analytics` (PR #99) and `agent-observability-foundation` (PR #100). `deny-event-correlation-report` was already on the dual-schema pattern; `scope-drift-monitor` has no KQL files (it queries the Office 365 Management API via PowerShell).
  - **H2** (managed-identity-first auth in Python analyzers): the two target solutions are PowerShell-only (no Python analyzers); their PowerShell scripts already adopted MI-first in prior releases.
- No PR opened for monitoring-analytics. Tracking comment posted on #127.

### Fixed
- **unrestricted-agent-sharing-detector**: PowerShell parse error in `Restore-AgentSharingFromEvidence.ps1` — escaped `$agentId:` to `${agentId}:` in 7 interpolated strings (Linux pwsh in CI parses `$variable:` as scope-qualified variable; Windows pwsh is more lenient). All 7 occurrences fixed. Local Parser::ParseFile now passes on both platforms.

### Notes
- All 5 PRs validated locally before push: `lint-odata-columns.py` (0 violations across 695–701 files), per-solution pytest (84 tests passing across the wave), language linter clean.
- No `solutions.json` or per-solution version-manifest changes required — H items were additive features that did not change manifest schema.
- Out of scope this wave: ~39 M items + ~32 Defer items remain in the 6 triage aggregate issues for the next cycle. Issue #123 (agent-intake pilot validation) is tenant-dependent and remains open separately.

---

---

## [Unreleased] - 2026-Q2 — CI tooling

### Added — scripts/lint-optionset-values.py REPORT-ONLY linter

- New `scripts/lint-optionset-values.py` detects `fsi_*` Picklist option-set definitions that use Value entries below the Dataverse `100000000` floor (the root cause of the cross-solution-integration `IntegrationConfig.psm1` zone-normalization bug class, where solution A defines a set 0-based while solution B reads it as 100000000+).
- Three layered allowlists suppress known-legitimate 0-based cases:
  - TwoOption / Boolean attributes (Dataverse contract — `TrueOption: {Value: 1}` / `FalseOption: {Value: 0}`).
  - `style-decisions.md` §9 shared sets (`fsi_acv_zone`, `fsi_acv_severity`) — deferred for a coordinated cross-solution migration.
  - Solution-internally-consistent sets: `compliance-dashboard` (8 picklists), `rag-source-validator` (6 picklists), `dr-testing-framework` (`fsi_drt_teststatus`, deferred to v2.1.0 per its CHANGELOG).
- User-managed allowlist at `scripts/.optionset-values-allowlist.txt` (one logical name per line, `#` comments allowed) for ad-hoc additions without editing the linter.
- Integrated into `.github/workflows/manifest-check.yml` as a new step with `continue-on-error: true` (REPORT-ONLY initial mode — flip to `--strict` in a follow-up PR once any new findings are triaged). Baseline scan across all 36 solutions is currently clean.
- 16-test unit suite at `scripts/tests/test_lint_optionset_values.py` covers Boolean exclusion, above-floor / below-floor / default-type detection, all three allowlist tiers, file-loading edge cases, and the three schema-script naming conventions.

---

## [Unreleased] - 2026-Q2 — Schema 1.5.0 (BREAKING)

### Changed (BREAKING)
- **schema 1.5.0**: `zones` is now a **required** field on every solution entry in `solutions.json`. Previously optional in 1.4.x (introduced in 1.4.2 as part of the additive zone-backfill). The schema 1.5.0 change is a tightening, not a data change — all 36 catalog solutions already have `zones` populated and confirmed (commit `ce82f83`).
- **`scripts/manifest.schema.json`**: appended `"zones"` to `required[]`; tightened the field description so it no longer says "Optional in 1.4.2".
- **`scripts/build-manifest.py`**: emits `schemaVersion: 1.5.0` (was `1.4.2`); `zones` is now projected unconditionally for every solution (was conditional on presence).
- **`solutions.json`**: regenerated with `schemaVersion: 1.5.0`. No data fields changed for any solution.

### Changed — documentation drift cleanup (same PR)
- Updated schema-evolution paragraphs in `CLAUDE.md`, `AGENTS.md`, `.github/copilot-instructions.md` to describe 1.5.0 as the current schema and 1.6.0 as the next breaking-change line.
- Replaced stale "Update the `LATEST_TAG` env var" wording in the same three files with the current behavior (auto-derived from `gh api repos/{repo}/releases/latest --jq .tag_name`; see Issue #39).

### Migration
- Consumers needing the old behavior (e.g., a parser that expects `zones` to possibly be absent) must pin to a 1.4.x release tag. Latest 1.4.x: **`v1.4.1`** (`gh release list --repo judeper/FSI-AgentGov-Solutions`).
- Consumers parsing `solutions.json` should expect `zones: string[]` (subset of `personal | team | enterprise`, `minItems: 1`) on every solution.
- The companion validator in `judeper/fsi-agentgov` (`scripts/validate_solutions_lock.py`) was widened in [judeper/fsi-agentgov#195](https://github.com/judeper/fsi-agentgov/pull/195) to accept both 1.4.x and 1.5.x ahead of this change.

### References
- Closes #37 (AC #4)

---

## [v1.5.0-preview] - Unreleased — agent-intake MVP (Express path)

### Added
- **`agent-intake` v0.1.0-preview** — new solution (lifecycle-ops domain, controls 1.2/1.7/2.1/2.13/3.1) implementing the Express-path MVP for FSI maker intake.
  - **Maker surface:** 10-question Power Pages form spec (`docs/portal-configuration.md`) + Teams adaptive card with FINRA 3110 sponsor attestation (`templates/sponsor-approval-card.json`).
  - **Workflow:** 3-flow Power Automate build instructions (`docs/flow-configuration.md`) — router, sponsor card, handoff. No exported flow JSON shipped (per Solution Content Policy).
  - **Dataverse schema:** 9 entities (`fsi_intakerequest`, `fsi_intakedatasource`, `fsi_intakerisksignal`, `fsi_intakereview`, `fsi_intakeapproval`, `fsi_intakedecisionlog`, `fsi_intakesponsorship`, `fsi_intakeauditevent`, `fsi_intakeretentionrecord`) + 7 global option sets. Decision log designed for FINRA 4511 / SEC 17a-4 / CFTC 1.31 7-year retention via Purview `FSI-AgentIntake-7yr` label.
  - **Classification engine:** `scripts/seed_classification_rules.py` computes tier/zone/decision-path from the 6 trigger answers; ships with `--self-test` (3/3 pass).
  - **Auto-detect (verified endpoints):** `autodetect_environments.py`, `autodetect_dlp_simulation.py`, `autodetect_purview.py`.
  - **Handoff:** `setup_entra_agent_id.py` mints Entra Agent ID on approval (GA May 1, 2026); `setup_purview_retention_label.py` emits one-time label spec + manual setup steps.
  - **Validation & ops:** `scripts/smoke_test.ps1` (7 read-only checks), `docs/pilot-deployment-runbook.md` (6-stage deploy + rollback), `docs/drift-detection-integration.md` (wires intake to four peer solutions).
  - **Research record preserved** under `agent-intake/research/` (Phase A reports, question catalog evaluation, intake form design, API verification spike, PO-resolved opens).
  - **Adoption polish** (added in same preview): `docs/maker-quick-start.md` (1-page maker guide), `docs/sponsor-cheat-sheet.md` (1-page sponsor guide with FINRA 3110 attestation walkthrough), `docs/onboarding-checklist.md` (Stage 0–8 customer admin checklist + rollback), `docs/decisions.md` (ADR consolidating 10 PO-locked decisions + OCC 2026-13 framing), Mermaid architecture diagram in `agent-intake/README.md`.
  - **Status & external gates** clearly enumerated at the top of `agent-intake/README.md` so reviewers can see what is shipped vs. what external steps remain (pilot walkthrough, governance review, customer admin Graph consents, Purview label creation, release tag).
- **Catalog updates:** README, AGENTS.md, CLAUDE.md, .github/copilot-instructions.md, mkdocs.yml nav (Lifecycle & Operations section), solutions.json lock file (now 36 entries, schemaVersion 1.4.2).

### Status
- Held as **draft PR** pending pilot-firm walkthrough. Out of scope for v0.1.0-preview: Standard / Full review paths, conversational intake via M365 Copilot declarative agent, reviewer queue Power App, automated environment provisioning. Targeted for v0.2.0+.

---

## [Unreleased] - 2026-Q2 — Microsoft Learn technical refresh (35 solutions)

Tracking summary: #119. All 35 catalog solutions reviewed against the latest Microsoft Learn documentation. agent-intake (still draft PR #42) is excluded.

### Changed — per-solution version bumps (all merged to main)
- **agent-config domain**: agent-communication-restriction-detector (#50), session-security-configurator (#54), credential-oversharing-detector (#55), generative-ai-config-auditor (#56), action-confirmation-auditor (#58).
- **lifecycle-ops domain**: coi-testing (#63), agent-registry-automation (#64), agent-365-lifecycle-governance (#65), dr-testing-framework (#66), pipeline-governance-cleanup (#69), environment-lifecycle-management (#70), message-center-monitor (#74).
- **access-identity domain**: agent-sharing-access-restriction-detector (#75), agent-access-monitor (#76), inactivity-timeout-enforcement (#80), cross-tenant-external-sharing-governance (#81), **conditional-access-automation v1.2.2 → v2.0.1 (major)** (#82).
- **content-data domain**: agent-knowledge-source-scanner (#86), content-moderation-monitor (#87), unrestricted-agent-sharing-detector (#88), file-upload-security (#92), mime-type-restrictions (#93), rag-source-validator (#94).
- **monitoring-analytics domain**: deny-event-correlation-report (#98), copilot-studio-analytics (#99), agent-observability-foundation (#100), hallucination-tracker (#103), scope-drift-monitor (#104).
- **compliance-audit domain**: compliance-dashboard (#108), finra-supervision-workflow v1.0.1 → v1.1.0 (#109), audit-compliance-manager (#110), hitl-workflow-governance (#114), model-risk-management-automation (#115), **cross-solution-integration v2.0.0 → v2.0.2** (#116), **segregation-detector v1.1.0 → v1.2.0** (#118).

### Changed — global / cross-solution
- **`scripts/shared/dataverse_client.py`** — now exposes both `auth_mode` (interactive/managed-identity/workload-identity/certificate/client-secret) AND `access_token` (externally-acquired bearer takes precedence). All Phase 3 solutions migrated to managed-identity-first auth. Client secrets are clearly marked `# legacy: dev-only` everywhere they remain.
- **`scripts/lint-odata-columns.py`** — flipped to `--strict`. CAA + CSI Dataverse logical-name bugs that necessitated the soft-gate are fixed.
- Across all 35 solutions: PnP.PowerShell 3.x cmdlet renames applied (`Get-PnPAzureADGroupMember` → `Get-PnPEntraIDGroupMember`), "Azure AD" branding removed (kept only in CHANGELOG historical entries), forbidden compliance language removed ("ensures compliance", "guarantees", "will prevent", "eliminates risk"), Microsoft Graph endpoints aligned to v1.0 where GA, KQL queries refreshed against current Application Insights / Log Analytics tables.

### Notes
- ~70 `CONSIDER` items remain documented in per-solution tracking issues as future work — none are blocking.
- agent-intake (PR #42) will get its own Microsoft Learn refresh once the draft is merged.

---

## [Unreleased] - 2026-Q2 — Repo health sweep

### Added
- **`RELEASING.md`** (new) — maintainer-facing release procedure, schema evolution policy, and the Issue #37 schema 1.5.0 unblock steps. Documents the four-stage process: (1) product-team review of the 35 inferred zone backfills, (2) sentinel-comment removal, (3) coordinated PRs with `judeper/fsi-agentgov` to make `zones` required, (4) issue closure. Includes rollback procedure.
- **`DEPLOYMENT-GUIDE.md`** — Related Documentation section now links to `RELEASING.md`.
- **`.github/workflows/ci-dotnet.yml`** (new) — Debug + Release builds of the FSI MIME validation plugin on `windows-latest` for every push/PR touching `mime-type-restrictions/src/**`. Soft-gate while baseline cleanup lands (Issue #38).
- **`mime-type-restrictions/src/ValidateMimeTypePlugin.csproj`** (new) — SDK-style csproj targeting net462 with explicit `Microsoft.CrmSdk.CoreAssemblies` 9.0.2.60 and `System.Text.Json` 8.0.5 package references. Supports unsigned CI builds and strong-name-signed local production builds (Issue #38).
- **`mime-type-restrictions/src/.gitignore`** (new) — excludes build outputs (`bin/`, `obj/`), strong-name keys (`*.snk`), and cosign signing artifacts.
- **`mime-type-restrictions/docs/build-and-sign.md`** (new) — full build / sign / verify guide. Covers local CI parity build, local production build (strong-name + ILRepack merge), customer verification of published DLL via SHA-256 + cosign Sigstore bundle + GitHub build provenance attestation.

### Changed — BREAKING (per-solution)
- **`conditional-access-automation` v1.2.2 → v2.0.0** — CAA Dataverse schema renamed from underscored snake_case SchemaNames to single-word PascalCase (Issue #36). Customers must drop and recreate the three CAA tables before upgrading. See `conditional-access-automation/CHANGELOG.md` for migration steps. The OData lint workflow (`.github/workflows/odata-lint.yml`) is now `--strict` and the soft-gate is removed.
- **`cross-solution-integration` v2.0.0 → v2.0.1** — adapts CAA history-table reader to the renamed columns. Now requires CAA v2.0.0+.

### Changed — CI / release ops
- **`.github/workflows/health-check.yml`** — `LATEST_TAG` is now auto-derived via `gh api repos/.../releases/latest --jq .tag_name` (Issue #39). The previous hardcoded `LATEST_TAG: v1.4.1` env value has been replaced by a "Resolve latest release tag" step. Maintainers no longer need to bump the workflow manually after each release. Fails loudly if no release exists.
- **`.github/workflows/codeql.yml`** — added `csharp` to the language matrix. C# analysis now runs on `windows-latest`, restores packages, and builds the plugin before invoking CodeQL. Python analysis remains on `ubuntu-latest` (Issue #38).
- **`.github/workflows/release.yml`** — new `build-plugin` job that compiles, hashes, **cosign keyless signs** (Sigstore OIDC), and attests the FSI MIME validation plugin DLL on every tagged release. The signed DLL + SHA-256 + signature + certificate + Sigstore bundle are attached to the GitHub Release alongside the existing source tarball + SBOMs + attestation (Issue #38).
- **`mime-type-restrictions` v1.1.0 → v1.2.0** — version bump for the new CI / release surface (no plugin behavior change).
- **`DEPLOYMENT-GUIDE.md`** — added "Post-Release Operations" section documenting the auto-derive mechanism + recommended post-release checklist.
- Doc references in `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md` updated to reflect the auto-derive behavior.

### Removed
- The `# legacy: dev-only` exception in `conditional-access-automation/.ralph-config.json` claiming that underscored SchemaNames were "correct and intentional" has been removed; that statement was incorrect.

---

## [v1.4.3] - Unreleased — message-center-monitor hardening + lab dry-run

### Changed
- **`message-center-monitor` v2.3.0 → v2.4.0** (PR #40): release-ready polish addressing 44 council findings.
  - **C1 fix (admin assessment preservation)**: `Invoke-MessageCenterSync.ps1` now routes update PATCH bodies through the new `Invoke-McmDvUpsertMessage` helper in `_Common.ps1`, which excludes all 7 admin-owned columns from the update payload. Previously the inline upsert clobbered any value an admin set during their assessment workflow.
  - **Schema correctness**: alternate key `fsi_MessageCenterIdKey` on `fsi_messagecenterid` enables idempotent upsert via `PATCH .../fsi_messagecenterlogs(fsi_messagecenterid='MCxxxxx')`.
  - **Auth modernization**: `-AuthMode` parameter on all 3 governance scripts (`ManagedIdentity` default; plus `WorkloadIdentity`, `Interactive`, `DeviceCode`, and `ClientSecret` legacy fallback). `SupportsShouldProcess` (`-WhatIf`/`-Confirm`) added.
  - **Mock-based test suite** (`tests/`): Pester (57 tests across 4 files) + pytest (13 tests). Hard-gated in CI on every PR; no tenant required.
  - Shared `_Common.ps1` helper module: retry-with-backoff REST helper, token cache with refresh-near-expiry, OData URL escape utilities, `Write-McmRedacted` log scrubber.
- **`message-center-monitor` v2.4.0 → v2.5.0** (PR #41): lab dry-run automation.
  - Added `lab/` directory with 8 numbered idempotent PowerShell scripts (`00`-`06`, `99`) that bootstrap a complete non-prod deployment and exercise the C1 fix end-to-end against a live Power Platform environment.
  - **Hard non-prod safety guard** on every mutating script — refuses to run unless `lab-config.json` contains the literal string `"I understand this lab must not target production"`. `-AllowProduction` switch bypasses with a loud warning.
  - **C1 verified end-to-end**: lab Step 6 back-dates `fsi_lastupdated` to force the update path, captures sync output and parses counters (`UpdatedRecords>=1` + `Failed==0`), and asserts byte-equality of all 7 admin-owned columns.
  - **Cross-process secret handoff** via gitignored owner-ACL'd `lab/.secret-handoff` file (the env-var approach broke when each `pwsh ./script.ps1` ran in its own process).
  - `docs/lab-dry-run.md` runbook with execution order, traceability matrix, non-prod ack section, and troubleshooting tree. README "Lab dry-run" section added above Quick Start.

---

## [v1.4.2]- Unreleased — Critique remediation (P0/P1/P2)

Addresses the external review of FSI-AgentGov + FSI-AgentGov-Solutions. Solutions-side scope only; framework-side items (evaluator coverage, etc.) tracked separately.

### Added — P0
- **Zone metadata model.** `manifest.schema.json` gained optional `zones` (subset of `personal|team|enterprise`), `dataClassification`, `dataResidency`, and `retention` fields. All 35 `*/manifest.yaml` files backfilled with inferred values (sentinel comments mark each entry for product-team review). `solutions.json` schemaVersion bumped to **1.4.2** (additive-only).
- **Framework version pin.** `manifest-check.yml` and `publish_docs.yml` now consume the framework at `${{ vars.FRAMEWORK_REF || 'v1.4.0' }}`, replacing the previous `main` reference. Override via repo variable `FRAMEWORK_REF` for trial upgrades.
- **`gitleaks` CI workflow** + `.gitleaks.toml` config — closes the `.mcp.json`-style leakage gap permanently.

### Added — P1
- **`ci-python.yml`** — ruff + pytest across all `*/scripts/**/*.py` (soft-gate while baseline clean-up lands).
- **`ci-powershell.yml`** — PSScriptAnalyzer + Pester for any `*.Tests.ps1` (soft-gate).
- **`language-rules.yml`** — bans absolute compliance language (`ensures compliance`, `guarantees compliance`) outside the rule-documenting files.
- **`odata-lint.yml` + `scripts/lint-odata-columns.py`** — narrow OData-context linter that checks Dataverse logical-name usage in `$select`/`$filter`/`$expand`/Web API paths/`LogicalName` JSON. Soft-gate; flip to `--strict` after the 5 known logical-name bugs in `conditional-access-automation` and `cross-solution-integration` are fixed.
- **`dependency-review.yml`** — GitHub-native dependency review on PRs.
- **`DEPLOYMENT-GUIDE.md` promoted to v1.0** — added Positioning, Pilot Path, and Licensing Footprint sections; replaced static layer/zone tables with `<!-- BEGIN:DEPLOY_LAYERS -->` and `<!-- BEGIN:ZONE_ROADMAP -->` blocks regenerated by `build-manifest.py` from manifests so version and zone drift is impossible.
- **README quickstart** — added "deploy one reference solution" walkthrough using `action-confirmation-auditor` as the canonical first deployment.
- **README positioning note** — clarifies that this catalog ships **reference implementations**, not turnkey deployable Power Platform `.zip` packages.
- **Status + Zones columns** in the README solutions table and site catalog.
- **Zones + Data classification badges** on every per-solution detail page.

### Added — P2
- **`SECURITY.md`** — vulnerability disclosure policy, supported versions, in-scope/out-of-scope classes, defensive controls inventory, coordinated disclosure with FSI-AgentGov.
- **`THREAT-MODEL.md`** — STRIDE-by-asset model covering repo content, customer-side execution, CI / supply chain, and the Dataverse plugin trust boundary; tracks open hardening items.
- **`release.yml`** — produces source tarball, SPDX + CycloneDX SBOMs, SHA-256 manifest, and (on tag) GitHub-native build-provenance attestations, attached to the GitHub Release.
- **`codeql.yml`** — Python CodeQL on push/PR/weekly schedule (C# added once `mime-type-restrictions/src/` gains a `.csproj`).
- **Managed-identity-first auth standard** documented in `AGENTS.md`. Client-secret paths flagged as `# legacy: dev-only`.

### Changed
- `scripts/build-manifest.py`:
  - schemaVersion bumped 1.4.1 → **1.4.2**.
  - `project_to_lock` now projects `zones`, `dataClassification`, `dataResidency`, `retention`.
  - README and site catalog tables gained Status + Zones columns.
  - Detail pages render Zones and Data classification badges.
  - New `emit_deploy_layers_block` and `emit_zone_roadmap_block` emit the deployment-guide tables driven by manifest data.
  - `copy_root_docs` accepts an `overrides` dict so the regenerated DEPLOYMENT-GUIDE flows through to the site copy without disk round-trips.

### Notes
- The 35-manifest zone backfill uses inferred values seeded by domain + control mappings. Each entry carries a sentinel comment (`# ZONE BACKFILL — INFERRED ...`) until the product team confirms.
- The `zones` field will move from optional to required in **schemaVersion 1.5.0** (coordinated with `judeper/fsi-agentgov`); 1.4.x remains additive-only.
- Plugin signing is intentionally deferred: `mime-type-restrictions/src/ValidateMimeTypePlugin.cs` has no `.csproj`. Tracked in `THREAT-MODEL.md` "Open items".
- Five known OData logical-name bugs remain (soft-gated by `odata-lint.yml`); see `THREAT-MODEL.md` for the list.

---

## [v1.4.1] - 2026-04-18

### Added
- `solutions.json` now includes per-solution `controls`, `dependencies`, and `status` fields (additive — schemaVersion bumped to **1.4.1** per the additive-only policy). Customers and downstream tools consuming the lock file can now see control mappings without crawling individual manifests.

### Notes
- No manifest changes required; existing `manifest.yaml` files already carried these fields. Only the projection in `scripts/build-manifest.py` was extended.

---

## [v1.4.0] - 2026-04-18

### Manifest unification + alignment with FSI-AgentGov v1.4

Replaces the centralized `scripts/solution-config.yml` with **per-solution `manifest.yaml`** files and adds a committed root-level **`solutions.json`** consumable by the framework's `refresh_solutions_lock.py`.

#### Added
- `<solution>/manifest.yaml` for all 35 solutions (canonical id = folder name; required fields: `id`, `name`, `description`, `version`, `status`, `domain`, `tier`, `controls`, `url`, `prerequisites`, `verification`).
- `scripts/manifest.schema.json` — JSON Schema (Draft 2020-12) enforcing the per-solution manifest contract.
- `scripts/build-manifest.py` — single generator for `solutions.json`, README catalog table (between `<!-- BEGIN:SOLUTIONS -->` markers), `site-docs/solutions/index.md`, all 35 detail pages, `site-docs/reference/control-mapping.md` (lists ALL 78 framework controls), and the home-page hero metrics block. Supports `--check` for CI drift detection.
- `solutions.json` at repo root, exposed at `https://raw.githubusercontent.com/judeper/FSI-AgentGov-Solutions/v1.4.0/solutions.json`.
- `.github/workflows/manifest-check.yml` — PR gate that fails when manifests reference unknown framework control IDs or generated artifacts drift from manifests. Pins framework `controls.json` via the v1.4 branch.

#### Changed
- 6 solutions previously linked to GitHub blob URLs from sidebar nav now have rendered detail pages: `cross-tenant-external-sharing-governance`, `agent-knowledge-source-scanner`, `hitl-workflow-governance`, `model-risk-management-automation`, `credential-oversharing-detector`, `agent-365-lifecycle-governance`.
- Display-name normalization: `Segregation of Duties Detector`, `Agent Access Governance Monitor`, `MIME Type Restrictions for File Uploads`, `Hallucination Feedback Tracker`, `Conflict of Interest Testing`.
- `compliance-dashboard` controls now include `3.4` (Incident Reporting and Root Cause Analysis).
- `agent-observability-foundation` controls populated: `1.7, 2.8, 2.9, 3.2`.
- `action-confirmation-auditor` controls corrected to `2.12, 1.10`.
- Pillar 4 control mapping page now lists all 9 SharePoint controls (4.1–4.9); previously listed only 4.3.
- Coverage Summary on control-mapping page now reads from manifest data (35 solutions).
- `scripts/publish_docs.yml` and the docs build pipeline both invoke `build-manifest.py` instead of `build-docs.py`.

#### Removed
- `scripts/solution-config.yml` — superseded by per-solution manifests.
- `scripts/build-docs.py` — superseded by `scripts/build-manifest.py`.

#### Schema evolution policy

> **`solutions.json` schema 1.4.x is additive-only.** New optional fields are allowed in 1.4.1 and later patch/minor releases. Field renames, new required fields, or shape changes (e.g., turning a string into an array) require **1.5.0** with a coordinated framework update so that consumers (currently `judeper/fsi-agentgov` lock-refresh tooling) upgrade in lockstep.

#### Stability guarantees

- **No solution folder renamed.** All `/<folder>/` paths in the repo are unchanged.
- **No `/solutions/<folder>/` URL changed** on the public site. Detail pages stay at `site-docs/solutions/<folder>/index.md`.
- Sidebar nav entries that previously pointed at GitHub blob URLs now point at internal pages with the same human-visible labels — no link redirects required.

#### Verification

```bash
python scripts/build-manifest.py            # idempotent regen
python scripts/build-manifest.py --check    # exits 0 only when in sync
mkdocs build --strict                       # site builds clean
```

After tagging, the framework's `refresh_solutions_lock.py --tag v1.4.0` consumes `solutions.json` from the raw GitHub URL.

---

## [Site Usability Review] - 2026-04-18

### Docs site — deduplication, lean overview pages, comment-coverage audit

Post-council-review sweep focused on GitHub Pages usability and code comment quality. Three commits:

- `docs(site): eliminate duplication — site-docs now includes canonical solution/docs at build` — renamed 28 solution `docs/*.md` files from UPPERCASE_UNDERSCORE to lowercase-hyphen so `build-docs.py`'s filename normalization produces consistent URLs; fixed internal cross-references.
- `docs(site): generate lean overview pages, sync versions, remove unused plugin` — rewrote `scripts/build-docs.py` to emit skim-friendly overview pages (preamble first paragraph only; Quick Start + Related Controls sections only; 25-line section cap with safe code-fence handling; Documentation table simplified). Resynced `scripts/solution-config.yml` versions to CHANGELOG heads for all 35 solutions. Removed unused `mkdocs-include-markdown-plugin`. All 35 overview pages now 23–65 lines (was 45–302).
- `docs(scripts): add PowerShell help blocks to 6 files missing .SYNOPSIS` — added `<# .SYNOPSIS #>` blocks to `conditional-access-automation.psm1` and the 5 private `Get-ZoneClassification.ps1` solution variants. All 211 PS files now parse with 0 errors.

### Code comment audit findings

- **PowerShell** (211 files): 6 missing help blocks — all fixed.
- **Python** (120 files): 0 missing module docstrings. Low-density files are predominantly schema-definition data literals (appropriately sparse).
- **KQL** (40 files): 0 missing headers; 54 % average density.

### AI context files updated

Added a **Docs Site Build Pipeline** section to `README.md`, `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` documenting:

- The two-step build (`build-docs.py` → `mkdocs build --strict`) used by CI.
- That `site-docs/solutions/*/` is gitignored and regenerated on every build.
- Where to edit to change overview structure (`build-docs.py`), content (solution `README.md`), and metadata (`solution-config.yml`).
- The verify-before-commit workflow.

### Validation

- `python scripts/build-docs.py` — 35 index pages, 149 nav-referenced files all present.
- `python -m mkdocs build --strict` — 0 errors.
- PowerShell AST parse over 211 files — 0 errors.

---

## [Council Review] - 2026-04-16

### Council Review — Autonomous Multi-Agent Audit

- Processed **34 solutions** via dual-model council review (GPT-5.4 + Claude Opus 4.6)
- Applied fixes to **31 solutions** (2 solutions had no issues, 1 partially fixed)
- **189 total fixes** across **136 files modified**
- Key fix categories:
  - **Dataverse column name mismatches** — Fixed dozens of schema-script misalignments (fsi_scantime → fsi_validationtime, entity set pluralization, snake_case → logical names)
  - **Product naming** — Updated "Azure AD" → "Microsoft Entra ID" across 60+ files
  - **Compliance language** — Replaced 20+ prohibited phrases ("ensures", "guarantees") with hedging language ("supports", "helps maintain")
  - **Missing schema columns** — Added exception audit trail columns (rejection notes, approval notes)
  - **Functional bugs** — Fixed KQL query bug (ResolutionRate always 0% for autonomous agents), exception expiration enforcement, resolution tracking
  - **Domain facts** — Created `.ralph-config.json` files for 8 solutions documenting key design decisions
- 0 items logged to REVIEW_NEEDED.md (all fixes applied directly)
- 0 GitHub Issues opened (no LOW confidence items requiring human review)

---

## Documentation Updates — 2026-04-09

### Changed
- **site-docs/index.md** — Fixed homepage metrics count from 33 to 35 solutions
- **unrestricted-agent-sharing-detector** — Added Native Agent Sharing Rules (GA May 2025) section referencing platform controls and positioning UASD as complementary audit/evidence layer
- **agent-sharing-access-restriction-detector** — Added Native Agent Sharing Rules (GA May 2025) section referencing platform controls and positioning ASARD for zone-based compliance auditing
- **agent-365-lifecycle-governance** — Added Relationship to Native Agentic Center of Enablement (2026 Wave 1) section explaining FSI-specific lifecycle enforcement beyond native CoE
- **environment-lifecycle-management** — Added Relationship to Native Agentic Center of Enablement (2026 Wave 1) section distinguishing provisioning-time governance from tenant monitoring
- **scope-drift-monitor** — Added Microsoft Purview Sensitivity Labels (2026 Wave 1) forward-looking note on complementary data classification
- **file-upload-security** — Added Microsoft Purview Sensitivity Labels (2026 Wave 1) forward-looking note on complementary data classification

---

## [Unreleased] — Remediation Sweep

### Fixed
- **Dataverse SchemaNames:** Corrected snake_case to PascalCase in agent-access-monitor (27 cols), content-moderation-monitor (24 cols), file-upload-security (35 cols + 3 tables)
- **Option set values:** Corrected to 100000000+ range across 8 solutions
- **Schema↔script column mismatches:** Aligned column names in 8 solutions (ARA, ASARD, ITE, ACRD, COD, CTSG, ALG, GAC)
- **Prohibited regulatory language:** Replaced "ensures compliance" / "guarantees" across 6 solutions
- **Sovereign cloud auth bug:** Fixed environment-specific endpoint handling in scope-drift-monitor
- **Version drift:** Synchronized catalog versions across 9 solutions (ASARD v1.0.3, CAA v1.2.0, CSI v1.0.1, DRTF v1.2.0, HT v1.0.0, ITE v1.0.4, MCM v2.2.0, RSV v1.1.0, AKSS v1.0.2)
- **Control mapping errors:** Corrected control references in 3 solutions
- **Stale file references:** Updated broken doc/script paths across 4 solutions

### Added
- **agent-365-lifecycle-governance:** Updated for Agent 365 GA (May 2026)
- **agent-knowledge-source-scanner:** PnP.PowerShell 3.x compatibility
- **generative-ai-config-auditor:** Added Get-GACValidationResults.ps1 governance script
- **Try/catch error handling:** Added structured error handling to 10+ scripts
- **MSAL.PS deprecation comments:** Added migration guidance comments across 13 solutions

### Removed
- **audit-compliance-manager:** Deleted 3 exported flow JSON files (content policy compliance)

---

## credential-oversharing-detector v1.0.0 — 2026-04-01

### Added
- Full solution release: scanning scripts, Dataverse schema, zone policies, evidence export, documentation
- 5 Dataverse tables with auto-generated schema documentation
- 6 PowerShell governance scripts for credential scope scanning and compliance
- Zone-based credential policy templates
- Teams adaptive card alert template
- Graduated from v0.1.0-preview placeholder to complete solution

---

## hitl-workflow-governance v1.0.0 — 2026-04-02

### Added

- **HITL Workflow Governance v1.0.0** — Full solution for zone-based governance of Human in the Loop checkpoints in Copilot Studio agent flows
  - Dataverse schema: 3 tables — fsi_HitlCheckpointResult (per-agent scan results), fsi_HitlCheckpointException (approved exceptions), fsi_HitlScanRun (immutable audit trail)
  - Python deployment: create_hwg_dataverse_schema.py (with --output-docs), create_hwg_environment_variables.py, create_hwg_connection_references.py, deploy.py
  - PowerShell scan scripts: Get-AgentHitlSettings.ps1, Test-HitlWorkflowCompliance.ps1, Start-HitlValidationRunbook.ps1
  - Evidence export: Export-HitlGovernanceEvidence.ps1 (JSON + SHA-256 sidecar), Test-EvidenceIntegrity.ps1
  - Governance validation: Test-HitlCheckpointConfiguration.ps1 for zone-based HITL policy enforcement
  - Private helper modules: HWGClient.psm1, Connect-EnvironmentDataverse.ps1, Get-ExpectedHitlPolicy.ps1, zone classification
  - Templates: hitl-zone-policy.json (zone requirements), adaptive-card-hitl-alert.json (Teams notification)
  - Documentation: prerequisites, flow configuration (manual build), Dataverse schema, troubleshooting
  - 6 environment variables, 2 connection references (Dataverse + Human in the Loop connector)
  - Supports Controls 2.12, 2.17, 1.10
- **Cross-Tenant External Sharing Governance v1.0.0** — Three-layer cross-tenant access governance for AI agents in FSI environments
  - Dataverse schema: 5 tables — fsi_approvedexternaltenant (allow list with alternate key), fsi_externalsharefinding (violations with composite dedup key), fsi_tenantisolationrecord (daily Layer 1 audit), fsi_entractarecord (weekly Layer 2 audit), fsi_crosstenantcomplianceevent (LTR-enabled immutable audit log)
  - Python deployment: create_ctsg_dataverse_schema.py, create_ctsg_environment_variables.py, create_ctsg_connection_references.py, deploy.py
  - PowerShell scripts: Deploy-CrossTenantBaseline.ps1, Validate-CrossTenantCompliance.ps1
  - Power Automate flows (documentation-only): tenant isolation validation, external agent share detection (5-value guest detection method), Entra CTA audit, tenant onboarding (dual-approval with Expired timeout), remediation (approval-gated), annual review reminders (90/30/overdue)
  - Two Managed Identities: MI-CrossTenantReadOnly (Flows 1-3, 6), MI-CrossTenantReadWrite (Flows 4-5)
  - 12 environment variables including feature flag and CTA baseline configuration
  - Templates: approved tenant sample, Adaptive Card v1.2 templates
  - Feature-flagged via IsCrossTenantGovernanceEnabled; depends on agent-registry-automation and unrestricted-agent-sharing-detector
  - Supports Controls 1.1, 1.18 (primary), 2.1, 2.8, 3.1, 1.11
- **Model Risk Management Automation v1.0.0**— Automated OCC 2011-12 / SR 11-7 model risk management for AI agents
  - Dataverse schema: 6 tables — fsi_modelinventory (with alternate key), fsi_mrmriskrating, fsi_validationcycle, fsi_validationfinding, fsi_monitoringrecord, fsi_mrmcomplianceevent (LTR-enabled immutable)
  - Python deployment: mrm_client.py, create_mrm_dataverse_schema.py, create_mrm_environment_variables.py, create_mrm_connection_references.py, deploy.py
  - PowerShell scripts: Deploy-MRM-Baseline.ps1, Validate-MRM-Compliance.ps1
  - Power Automate flows (documentation-only): inventory sync, risk scoring, validation workflow, performance monitoring, Agent Card generation, revalidation trigger
  - Power Apps (documentation-only): MRM Submission Portal (Canvas, 4 screens), Validation Workbench (Model-Driven)
  - Power BI dashboard (documentation-only): MRM Compliance Dashboard with 5 report pages
  - SharePoint: Agent Card Library with Word template + JSON fallback
  - Templates: 4 Adaptive Card v1.2 templates, sample config, Agent Card content structure
  - Feature-flagged via IsMRMAutomationEnabled; depends on agent-registry-automation
  - Supports Controls 2.6 (primary), 2.5, 2.9, 2.11, 2.13, 3.1, 1.2
- **Agent 365 Lifecycle Governance v1.1.0** — Automated lifecycle governance for AI agents using Microsoft Agent 365, Entra ID Governance, and Power Platform
  - Dataverse schema: 5 tables — fsi_agentlifecyclerecord (with alternate key), fsi_sponsorassignment, fsi_accessreview, fsi_deactivationrequest, fsi_lifecyclecomplianceevent (LTR-enabled immutable)
  - Python deployment: create_alg_dataverse_schema.py, create_alg_environment_variables.py, create_alg_connection_references.py
  - PowerShell scripts: Deploy-LifecycleGovernance-Baseline.ps1, Validate-LifecycleCompliance.ps1
  - Power Automate flows (documentation-only): sponsor enforcement, access reviews, inactivity detection, deactivation, sponsor monitoring, deletion hold
  - Templates: Adaptive Card v1.2 sponsor assignment notification, sample lifecycle configuration
  - Feature-flagged via IsAgent365LifecycleEnabled (gates all Agent 365 API calls until GA)
  - Supports Controls 2.3 (primary), 1.2, 1.11, 2.1, 2.8, 2.12, 3.1
- **Agent Registry Automation v1.0.0**— Automated discovery, registration, approval, and lifecycle governance of AI agents
  - Dataverse schema: fsi_agentinventory (with alternate key), fsi_registrationrequest, fsi_agentcomplianceevent (LTR-enabled), fsi_ownershipaudit
  - Python deployment: ara_client.py, create_dataverse_schema.py, create_environment_variables.py, create_connection_references.py, deploy.py
  - PowerShell scripts: Deploy-AgentRegistry-Baseline.ps1, Validate-AgentRegistry-Compliance.ps1
  - Power Automate flows (documentation-only): daily discovery, registration approval, Entra sync, orphan detection
  - Supports Controls 1.2 (primary), 1.7, 2.1, 2.13
- **Agent Knowledge Source Scanner v1.0.0** — New solution for item-level permission scanning in agent knowledge source SharePoint libraries
  - `Get-KnowledgeSourceItemPermissions.ps1` — PnP PowerShell script enumerating item-level permissions with agent-context-aware risk scoring (CRITICAL/HIGH/MEDIUM/LOW)
  - Sensitivity label cross-reference with configurable tier mapping
  - Agent user scope comparison via security group or UPN list
  - CSV/JSON input support for multi-library scanning from prior scan output
  - `item-scope-config.sample.json` configuration template
- **Compliance Dashboard — Exchange Coverage** — Extended with Exchange Online compliance signal collection
  - `Get-ExchangeComplianceData.ps1` — Graph API script collecting external forwarding rules, DLP alerts, shared mailbox access, distribution list external membership
  - `exchange-config.sample.json` configuration template with scan scope, risk thresholds, domain allow-list
  - Updated architecture diagram, data sources, and documentation to include Exchange as a data source
  - Updated dataverse-schema.md with Exchange evidence mapping to fsi_complianceevidence
  - Updated flow-configuration.md with Exchange API calls for CD-EvidenceCollector planned flow

- **Action Confirmation Auditor** — New `Test-UserDefinedActionMessages.ps1` governance script validates the Copilot Studio "User-Defined Action Messages" toggle per zone policy (Zone 3 required, Zone 2 recommended, Zone 1 optional). Supports Control 1.23.
- **Generative AI Config Auditor** — Two new compliance rules:
  - Rule 5 (`UnauthorizedModelKnowledge`): Validates "Use AI general knowledge" / Model Knowledge toggle against zone policy (Zone 3 disabled, Zone 2 requires approval, Zone 1 allowed)
  - Rule 6 (`UnauthorizedSemanticSearch`): Validates Semantic Search toggle against zone policy (Zone 3 requires approval, Zone 2 allowed with logging, Zone 1 allowed)
  - Updated `Get-ExpectedGenAIPolicy.ps1`, `Get-AgentGenAISettings.ps1`, `Compare-GenAIConfigCompliance.ps1`, and Dataverse schema
- **Unrestricted Agent Sharing Detector** — New `Test-AgentSharingCompliance.ps1` and `Get-ExpectedSharingPolicy.ps1` governance scripts for zone-based sharing compliance validation; new `uasd_client.py` Dataverse client

### Fixed

- **Compliance Dashboard documentation drift:** Corrected stale 62-control / 71-control references in active docs to the validated 78-control baseline across README, deployment checklist, Power BI template guidance, troubleshooting, and control master table expectations
- **UASD Adaptive Card:** Corrected "Run Audit Script" URL to match actual deployment guide path; corrected "View Documentation" URL to point to Control 1.1 (was incorrectly referencing Control 2.24)

### Previously Added

- **UASD v1.0.2** — Flow 4 (`UASD-Exception-Expiration-Monitor`) build instructions: proactive exception expiration handling with configurable warning threshold and Teams alerts
- **Deployment Guide v0.1** — Use-case mapping, solution layers, and Compliance Dashboard integration sequencing

- **DR Testing Framework v1.0.0** - Automated disaster recovery testing for AI agents
  - 4 test scenarios: Agent Restore, Environment Failover, Data Recovery, Full DR
  - RTO/RPO measurement and comparison
  - Validation checks for agent, connector, data, and security
  - PowerShell script: Invoke-DRTest.ps1
  - Gap identification and tracking
  - Evidence export for compliance
  - Supports Controls 2.4, 2.1, 1.9

- **Hallucination Tracker v1.0.0** - Feedback aggregation for hallucination pattern analysis
  - Multi-source feedback collection (user, supervisor, automated)
  - 5 hallucination categories with severity scoring
  - Pattern detection and clustering
  - Agent accuracy scoring and rating
  - Python script: analyze_patterns.py
  - Supports Controls 3.10, 2.9, 2.12

- **COI Testing Framework v1.0.0** - Conflict of interest testing for agent recommendations
  - Test categories: Proprietary bias (3), Suitability (3), Fee transparency (2), Cross-selling (2)
  - Python test runner: run_coi_tests.py
  - Scheduled and on-demand test execution
  - FINRA Supervision Workflow integration
  - Supports Controls 2.18, 2.11, 2.5

- **RAG Source Validator v1.0.0** - Integrity validation for RAG knowledge sources
  - Dataverse schema: fsi_knowledgesource, fsi_validationresult, fsi_sourcechange
  - Security roles: RSV Viewer, RSV Validator, RSV Admin
  - PowerShell script: Invoke-SourceValidation.ps1
  - SHA-256 hash validation, schema drift detection, freshness monitoring
  - Supports SharePoint, Dataverse, Azure Blob sources
  - Supports Controls 2.16, 1.7, 2.13

- **Scope Drift Monitor v1.0.0** - Detect agent data access beyond declared scope
  - Dataverse schema: fsi_agentscope, fsi_scopeitem, fsi_scopeviolation, fsi_expansionrequest
  - Security roles: SDM Viewer, SDM Analyst, SDM Admin
  - PowerShell script: New-AgentBaseline.ps1
  - Scope expansion workflow with data owner and security approval
  - Complete documentation: prerequisites, schema, baseline configuration
  - Supports Controls 1.14, 1.4, 1.5

- **Segregation of Duties Detector v1.0.0** - Role conflict detection for Maker/Checker enforcement
  - Dataverse schema: fsi_conflictrule, fsi_sodviolation, fsi_sodexception, fsi_sodauditlog
  - Security roles: SoD Viewer, SoD Analyst, SoD Admin
  - PowerShell scripts: Invoke-SoDScan.ps1, Import-ConflictRules.ps1
  - Default rule sets: Maker/Checker (4), Segregation (3), Privileged Access (3)
  - Complete documentation: prerequisites, schema, conflict rules, troubleshooting
  - Supports Controls 2.8, 2.1, 2.3

- **Compliance Dashboard v1.0.0-beta** - Aggregated compliance reporting across 71 controls
  - Dataverse schema: fsi_controlmaster, fsi_controlassessment, fsi_compliancescore, fsi_complianceexception, fsi_complianceevidence
  - Security roles: CD Viewer, CD Assessor, CD Admin
  - Power Automate flows: CD-ScoreCalculator, CD-ExceptionMonitor, CD-EvidenceCollector
  - Python script: load_sample_data.py for demo data
  - Complete documentation: prerequisites, schema, flows, Power BI setup, DAX measures, troubleshooting
  - Control master data: All 71 controls with zone applicability and weights
  - Supports Controls 3.3, 3.1, 3.2
  - **Note:** Beta release - documentation and schemas complete, Power BI template requires manual creation

- **Conditional Access Automation v1.0.0** - CA policy deployment and compliance monitoring for AI workloads
  - 8 policy templates for Copilot Studio, Agent Builder, and M365 Copilot
  - PowerShell scripts: Deploy-CAPolicies.ps1, Test-PolicyCompliance.ps1, Register-ServicePrincipal.ps1
  - Zone-based policy requirements (Zone 1: risk-based, Zone 2: always MFA, Zone 3: MFA + compliant device)
  - Policy drift detection and compliance monitoring
  - Break-glass account exclusion enforcement
  - ELM integration for automated policy deployment on environment provisioning
  - Complete documentation: prerequisites, templates, deployment guide, compliance monitoring, troubleshooting
  - Supports Controls 1.11, 1.23, 1.18

- **FINRA Supervision Workflow v1.0.0** - Automated supervision queue for AI agent outputs (FINRA 3110)
  - Dataverse schema: SupervisionQueue, SupervisionLog, SupervisionConfig tables
  - Security roles: FSW Supervisor, FSW Queue Manager, FSW Admin, FSW Auditor
  - Python scripts: deploy.py, export_supervision_evidence.py
  - Complete documentation: prerequisites, schema, security roles, flow configuration, Communication Compliance setup, Power BI dashboard, troubleshooting
  - Integration with Communication Compliance API for flagged content ingestion
  - Zone/tier-based SLA configuration with automatic escalation
  - Evidence export with SHA-256 integrity hashing for regulatory examination
  - Supports Controls 2.12, 1.10, 1.7

- **Environment Lifecycle Management v1.0.1** - Automated Power Platform environment provisioning
  - Python scripts: Service Principal registration, quarterly evidence export, role verification, immutability validation
  - Complete documentation: prerequisites, Dataverse schema, security roles, flow configuration, Copilot setup
  - Templates: EnvironmentRequest JSON sample, Copilot Studio output schema
  - SETUP_CHECKLIST.md for phased deployment

### Changed

- **Catalog reconciliation:** Updated root README.md and `site-docs/solutions/index.md` to align the published inventory to 33 live solutions and the validated 78-control framework baseline, bringing existing live entries and current version labels back in sync without rewriting historical release notes
- **Preview/live boundary:** Both `hitl-workflow-governance` and `credential-oversharing-detector` have since graduated to v1.0.0 live solutions
- **Entra terminology cleanup:** Active documentation now uses Microsoft Entra ID naming for app registrations, connector labels, licensing references, and resource URI tables where current product terminology applies
- **Agent 365 governance boundary:** Clarified that Agent 365 Lifecycle Governance complements — rather than duplicates — native Agent 365 Admin Center inventory, pending request, ownerless-agent, and overview analytics surfaces
- Updated root README.md to include Environment Lifecycle Management
- Enhanced boundary-check.py hook with cross-repository access to FSI-AgentGov
- Added Python/pip permissions to settings.json
- Added hooks configuration to settings.json (previously only in settings.local.json)

---

## Previous Releases

Individual solution changelogs:

- [DR Testing Framework](./dr-testing-framework/CHANGELOG.md) - v1.0.0
- [Hallucination Tracker](./hallucination-tracker/CHANGELOG.md) - v1.0.0
- [COI Testing Framework](./coi-testing/CHANGELOG.md) - v1.0.0
- [RAG Source Validator](./rag-source-validator/CHANGELOG.md) - v1.0.0
- [Scope Drift Monitor](./scope-drift-monitor/CHANGELOG.md) - v1.0.0
- [Segregation of Duties Detector](./segregation-detector/CHANGELOG.md) - v1.0.0
- [Compliance Dashboard](./compliance-dashboard/CHANGELOG.md) - v1.0.0-beta
- [Conditional Access Automation](./conditional-access-automation/CHANGELOG.md) - v1.0.0
- [FINRA Supervision Workflow](./finra-supervision-workflow/CHANGELOG.md) - v1.0.0
- [Environment Lifecycle Management](./environment-lifecycle-management/CHANGELOG.md) - v1.1.2
- [Message Center Monitor](./message-center-monitor/CHANGELOG.md) - v2.5.0
- [Pipeline Governance Cleanup](./pipeline-governance-cleanup/CHANGELOG.md) - v1.0.8
- [Deny Event Correlation Report](./deny-event-correlation-report/CHANGELOG.md) - v2.0.0
