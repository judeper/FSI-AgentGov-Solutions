# Changelog

All notable changes to the **agent-intake** solution will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- **Lab functional-verification trigger helper:** Added `scripts/New-IntakeSubmission.ps1`, a lab tool that creates a pristine `fsi_intakerequest` row in `Submitted` status (maker-supplied inputs and the T1-T6 answers only, with no router output columns) so the router flow (Flow 1) fires its "row added/modified AND status = Submitted AND blank `fsi_decisionpath`" trigger and performs the routing itself. The existing `seed-test-data.ps1` fixtures land in terminal states for reviewer-app and smoke checks and do not exercise the router; this helper supplies the missing on-demand submission. It reads the validated `scripts/seed-test-data/request-*.json` fixtures (all five scenarios), regenerates a unique `fsi_requestid` per run to avoid alternate-key collisions, supports `-DryRun` and `-RemoveAfter`, and reuses the lab's Azure CLI / `DATAVERSE_ACCESS_TOKEN` auth pattern. Verified end-to-end by a live create → status check → delete cycle on the sandbox tenant.
- **Unattended lab-cycle support:** Added a `-SkipPurviewLabel` switch to `scripts/deploy.ps1` (threaded through `lab/Invoke-Deploy.ps1` and `lab/config.example.json` as `deploy.skipPurviewLabel`) that skips the Stage 3 Purview retention-label creation step — required for fully unattended lab deployments in a headless shell, where the interactive `Connect-IPPSSession` path would otherwise block. Blueprint, consent, and the Purview verification probe still run. Use only when the retention labels already exist on the tenant. Added `lab/Test-LabAuthReadiness.ps1`, a preflight that checks Conditional Access posture, Dataverse + Microsoft Graph token acquisition, the Power Platform CLI profile, environment SKU, and required PowerShell modules before an unattended run. Validated end-to-end by a live teardown → redeploy → seed → smoke cycle on a sandbox tenant.

### Fixed

- **Flow-build doc reviewer-path clarity (FV0 validation):** Clarified three naming points in `docs/flow-configuration.md` surfaced by an owl-mode validation of the doc against the live Dataverse schema (which found zero schema drift across 98 column references, 22 option-set values, 9 tables, and 4 environment variables). Added a footnote that the `fsi_intake_reviewdecision` option set is bound to the `fsi_reviewoutcome` column on `fsi_intakereview` (there is no `fsi_reviewdecision` column) and should be used in OData filters; and clarified that `${fsi_reviewerattestation}` and `${fsi_reviewerappurl}` in the reviewer card step are card-template placeholders (sourced from `fsiRoleAttestationCatalog` in `templates/reviewer-notification-card.json` and the `fsi_intake_reviewerappurl` environment variable respectively), not Dataverse columns. `scripts/seed-test-data.ps1` and `scripts/smoke_test.ps1` passed `(Get-AzAccessToken -ResourceUrl ...).Token` straight into the `Bearer` Authorization header. Starting Az.Accounts 5.0.0 (Az 14.0.0), `Get-AzAccessToken` returns `.Token` as a `SecureString` by default, so on an Az-module-only host (no `az` CLI) the header degraded to `Bearer System.Security.SecureString` and every Dataverse call would 401. Both scripts now type-guard the token and convert via `ConvertFrom-SecureString -AsPlainText` when a `SecureString` is returned, remaining compatible with pre-5.0 String output. Verified against [Protect secrets in Azure PowerShell](https://learn.microsoft.com/powershell/azure/protect-secrets) and the [Get-AzAccessToken reference](https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken). (technical accuracy review)

- **Lab-readiness doc accuracy:** Removed stale `v0.2`/`v0.3`/`v0.4` capability statements from customer-facing docs that contradicted the shipped Express + Standard + Full paths. Updated the README "Zone applicability" table and "Roadmap" sections, and the `docs/maker-quick-start.md` Standard/Full path references, to reflect that all three paths ship in v1.0.0-preview. Verified the Microsoft Entra Agent ID handoff (`scripts/setup_entra_agent_id.py`) against the current Microsoft Graph v1.0 `Create agentIdentity` API (path, request body, and `AgentIdentity.Create.All` / `AgentIdentity.CreateAsManager` / `AgentIdentity.Read.All` permissions) per `LAB-VALIDATION.md`.
- **Wave 6 P4b:** Empty catch blocks now log via `Write-Verbose` instead of silently swallowing errors. Output is unchanged unless caller passes `-Verbose`.
- **High**: Drift-handoff Standard-path `reviewerAttestations` constraint required `InfoSec` + `Compliance`, but the classifier always emits `InfoSec` + `Privacy` and adds `Compliance` only when `fsi_t4handlesnpi` is positive. Updated the Standard-path `allOf` in `templates/drift-handoff-payload-schema.json` (lines 561-594) to require `InfoSec` and `Privacy` (the always-present pair) so Standard requests with zero NPI hits can produce a valid payload. (council review H-1)
- **High**: `fsi_intake_status` values `InReview` (100000011) and `LiveTracking` (100000012) — present in `scripts/create_fsi_intake_dataverse_schema.py` and referenced by `docs/flow-configuration.md` — were missing from `templates/reviewer-app-spec.json` and the smoke-test `ChoiceMap`. Added both values to the reviewer-app spec and expanded the smoke-test `ChoiceMap` to cover all 13 schema values (Draft through LiveTracking). (council review H-2, M-2)
- **High**: `fsi_intakeretentionrecord` was absent from every reviewer security role's `tablePrivileges` in `templates/reviewer-app-spec.json`, leaving the Governance Lead with no visibility into Purview retention stamping for audit. Added `fsi_intakeretentionrecord` with `Read` at `Global` depth to all six security roles (InfoSec, Privacy, Compliance, Legal, MRM, Governance Lead). (council review H-3)
- **High**: `fsi_intakeretentionrecord` was referenced by all six reviewer roles' `tablePrivileges` (council H-3) but was missing from the top-level `tables` array in `templates/reviewer-app-spec.json`, so `scripts/provision_reviewer_app.ps1` raised "Table 'fsi_intakeretentionrecord' ... is not present in the spec" and Stage 5 (reviewer app) failed during live deployment. Added the table to the `tables` array (read-only), completing H-3. Surfaced by an end-to-end live lab validation on a sandbox tenant.
- **Module prerequisites:** `scripts/deploy.ps1` now declares `powershell-yaml` (>= 0.4.0) in `#Requires` — it is used at runtime by `Get-PolicyDocument` (`ConvertFrom-Yaml`) but was previously undeclared — and no longer hard-requires `ExchangeOnlineManagement`; that module is now checked conditionally (only when Purview label creation runs, that is, not with `-SkipPurviewLabel`) and is bootstrapped at runtime by `scripts/setup_purview_retention_label.ps1` when actually needed, so a Purview-skipping unattended host can run without the Exchange module. `lab/Test-LabAuthReadiness.ps1` guards Conditional Access `signInFrequency` parsing against policies that omit `sessionControls`.
- **Medium**: `templates/mrm-handoff-payload-example.json` used `"agentType": "Copilot Studio"` instead of the canonical `fsi_intake_agenttype` label `"Copilot Studio (classic)"`. Updated the example to match the option-set label. (council review M-3)
- **Medium**: `tests/validators/validate_policy_yaml.py` validated `audience_to_zone` only as a `dict`. Added type and value checks that require all five expected audience keys (`Just me`, `My team`, `My department`, `Anyone in the firm`, `External users`) and confirm each value is an `int` in `{1, 2, 3}` (rejecting `bool` explicitly so `True` cannot pass as zone 1). (council review M-4)

### Changed

- **Operator ergonomics (Wave 6 P4a):** State-changing scripts now support `-WhatIf` and `-Confirm` switches via `SupportsShouldProcess`. Existing callers see no behavior change unless they explicitly pass `-WhatIf`.
- **Medium**: Added a code comment to `scripts/create_fsi_intake_dataverse_schema.py` `fsi_intake_auditeventtype` definition clarifying that the option set is an intentional reference catalog and is NOT deployed by `deploy.ps1` because the backing `fsi_eventtype` column is a String (not Picklist) to permit customer extension. (council review M-1)
- **Medium**: Added a `_comment` field to `scripts/seed-test-data/request-cross-border-deny.json` `expectedClassification` documenting that `pathUsed = Standard` depends on the default `audience_to_zone` mapping in `templates/policy-lookup-tables.yaml`; if a customer remaps `My team` to Zone 1, the classifier routes the fixture to Full instead. (council review M-5)
- **Minor**: Added a code comment to `tests/validators/validate_question_catalogs.py` `EXPECTED_QUESTION_COUNTS` documenting the derivation (one entry per `| <ID>` row in the corresponding `docs/intake-questions-<path>.md`) and the maintenance contract. (council review L-4)
- **Issue #123 preflight (de-risking):** Hardened the dry-run preview on both live-tenant setup paths so an operator can review the exact outbound request without contacting Microsoft. `scripts/setup_entra_agent_id.py --dry-run` now emits `method` (`POST`) and `apiVersion` (`v1.0`) alongside the URL and payload, surfaces the conditional reviewer-evidence `PATCH` fallback, and lists `AgentIdentity.Create.All` first as the least-privileged create permission. `scripts/setup_purview_retention_label.py --dry-run` and `scripts/setup_purview_retention_label.ps1 -DryRun` now produce an offline preview of the exact `New-ComplianceTag` commands without installing `ExchangeOnlineManagement` or connecting to Security & Compliance PowerShell. The create request shapes themselves are unchanged and still require a live tenant to confirm a `201`/label creation. Verified against the Microsoft Graph v1.0 [Create agentIdentity](https://learn.microsoft.com/graph/api/agentidentity-post?view=graph-rest-1.0) and [Create retentionLabel](https://learn.microsoft.com/graph/api/security-labelsroot-post-retentionlabel?view=graph-rest-1.0) references and the Exchange [New-ComplianceTag](https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag) cmdlet.
- **Issue #123 live-tenant prerequisites (docs):** Added a "Live-tenant prerequisites and admin consent" section to `docs/identity-records-automation.md` covering, per path, the required admin role, least-privilege permission/scope, and admin-consent step a live operator needs before running the two setup scripts — Path A (Microsoft Entra Agent ID create: `AgentIdentity.Create.All` least-privilege, admin role **Agent ID Administrator** / **Agent ID Developer**) and Path B (Microsoft Purview retention label: PowerShell `New-ComplianceTag` production path with the **Compliance Administrator** / **Records Management** role group, plus the now-GA-at-v1.0 Graph create alternative using delegated `RecordsManagement.ReadWrite.All`, application permissions not supported). Corrected the prior "Graph beta" framing of the Path B create endpoint to GA at v1.0 (beta also available), repointed the dangling `setup-prerequisites.md` references in `docs/pilot-validation-gap-analysis.md` to the new section, and refreshed the Gap 1 / Gap 2 prerequisite role and scope facts. Live acceptance (a real `201` / label creation and portal screenshots) still requires a tenant. Verified against the Microsoft Graph v1.0 [Create agentIdentity](https://learn.microsoft.com/graph/api/agentidentity-post?view=graph-rest-1.0) and [Create retentionLabel](https://learn.microsoft.com/graph/api/security-labelsroot-post-retentionlabel?view=graph-rest-1.0) references and the Exchange [New-ComplianceTag](https://learn.microsoft.com/powershell/module/exchangepowershell/new-compliancetag) cmdlet.

### Notes

- Reviewer-app security-role privilege delta (H-3): all six roles (InfoSec, Privacy, Compliance, Legal, MRM, Governance Lead) gain `fsi_intakeretentionrecord` `Read` at `Global` depth. No existing privilege is changed or removed.
- Council review findings deferred (with rationale): L-1 (`fsiRoleAttestationCatalog` non-standard property in `reviewer-notification-card.json` — documentation-only; defer to a v1.1 card-template overhaul), L-2 (`sponsor-approval-card.json` Express-path language — Express-only by design until sponsor cards are introduced for other paths), L-3 (`autodetect_environments.py` `az login` error handling — small UX improvement, defer to v1.1), I-1 (shared `Get-ZoneClassification.ps1` zone-name inversion — FORBIDDEN shared asset per Wave 3 REFINEMENT 2; tracked as a cross-solution Wave 5 item), I-2 / I-3 / I-6 (informational, no action), I-4 / I-5 (positive observations).

## [1.0.0-preview] - 2026-05-16

### Added

- Added the v1.0.0-preview schema and policy foundations for three intake paths, including new option sets, status values, audit event inventories, and routing columns such as `fsi_routingtopology`, `fsi_quorumrequired`, `fsi_parallelreviewersjson`, `fsi_mrmrequired`, `fsi_mrmhandoffstatus`, `fsi_standardfullquestionsjson`, `fsi_appealofid`, and `fsi_nonmrmquorummet` (`f10cabe`).
- Added refreshed Express questions plus the new Standard and Full question catalogs, including 22 Standard questions, 35 Full questions, and the overview map that explains when each pack is used (`4dfc9d0`).
- Added drift-detection handoff payload guidance for Standard and Full paths so downstream monitoring solutions can consume richer post-approval context (`2632f5a`).
- Added Microsoft Entra Agent ID blueprint automation with the `fsiReviewerAttestations` open-type payload pattern and extended Purview retention-label automation to cover reviewer attestations in the decision pack (`fa411b4`).
- Added MRM handoff integration to `model-risk-management-automation`, including alternate-key lookup guidance for `fsi_modelinventory` and status tracking for the intake handoff (`8f41f90`).
- Added a model-driven reviewer queues app and ADR-011 implementation notes, with the managed `.zip` artifact explicitly permitted for this app-only packaging scenario (`9f76e15`).
- Added a dedicated CI workflow with four validators and 42 pytest cases to keep the preview lab rebuild and schema docs aligned (`9f177be`).
- Added a full enablement suite for makers, sponsors, reviewers, admins, and demo operators so pilot teams can rehearse all three paths before broad rollout (`18dc8cf`).

### Changed

- Changed the classification model from Express-only routing to Express, Standard, and Full paths, with refreshed Express logic and policy mapping that now supports reviewer quorum, non-MRM quorum tracking, and MRM-required escalation (`6570da8`).
- Changed the maker experience to a multistep Power Pages form with progressive disclosure, plus PAC CLI scaffolding for the portal assets that can be automated today (`5a24d1b`).
- Changed the build guidance from the original Express-only flow set to 12 documented Power Automate flows (build instructions only, no exported JSON per repo policy), plus supporting PAC shell and prerequisites guidance (`1adf2d8`).
- Changed lab operations to a single-command `deploy.ps1` orchestrator with `-Teardown`, `-SeedTestData`, and `-DryRun`, five test data fixtures, and an expanded `smoke_test.ps1` with `-PathScope` and `-IncludeSeededDataChecks` (`3bc5400`).

### Removed

- Removed the remaining schema-gap caveats from the flow build guide once the missing request columns, status values, and audit-event inventories were added to the Dataverse model (`9461a38`).

### Fixed

- Fixed release-adjacent reconciliation issues across catalog field references, ruff `E402`, and `Write-Host` usage so the preview content is internally consistent for the v1.0.0-preview drop (`c1e32ec`).
- Fixed flow-spec-driven schema gaps by closing the open items around `fsi_appealofid`, the extra intake statuses, `fsi_nonmrmquorummet`, and the newer audit event values, then regenerating `docs/dataverse-schema.md` to match (`9461a38`).

### Security

- Extended records and identity automation so reviewer attestations, sponsor approvals, and Agent ID minting events can be retained and replayed as part of the same decision pack, which supports compliance with FINRA Rule 4511(a), SEC Rule 17a-4, and CFTC Rule 1.31 when customers complete the tenant-side retention and approval setup (`fa411b4`).

### Known limitations / v1.1 evolution

- `fsi_appealofid` is currently a Single Line of Text column; convert it to a self-lookup in v1.1.
- Microsoft Entra Agent ID `fsiReviewerAttestations` open-type field acceptance is pending live-tenant verification.
- PAC CLI cannot programmatically create Power Pages multistep form bindings; Stage 4 of `deploy.ps1` includes **MANUAL STEP REQUIRED** markers.
- Two legacy PSScriptAnalyzer warnings in `provision_power_pages.ps1` remain soft-gated as the current baseline.

## [0.2.0-preview] - 2026-05-06

### Changed — Microsoft Learn 2026-Q2 accuracy refresh

- Updated Microsoft Entra Agent ID handoff to the current Microsoft Graph v1.0 `POST /servicePrincipals/microsoft.graph.agentIdentity` create action with `agentIdentityBlueprintId`, sponsor binding, and create-specific permissions (`AgentIdentity.CreateAsManager` or `AgentIdentity.Create.All`).
- Updated Purview retention-label guidance: production deployments use the Purview portal or Security & Compliance PowerShell; Graph beta create is documented as delegated-only preview guidance.
- Replaced legacy HTTP-style sponsor-card actions with `Action.Submit` for the Power Automate "Post adaptive card and wait for a response" pattern.
- Aligned Power Pages and Power Automate docs with Dataverse logical names from the schema script and added the canonical Express-form/computed columns to the schema.
- Fixed Dataverse schema deployment calls to match `scripts/shared/dataverse_client.py` (`create_option_set(metadata)` and `create_column(entity, metadata)`) and added managed-identity/workload/certificate/access-token auth options.
- Updated DLP simulation to use Business, Non-business, and Blocked connector groups and detect mixed Business/Non-business connector requests.
- Changed the preview catalog tier to Tier 1 because this is a foundational pre-build intake control for agent governance, while retaining the Express path for Tier-3/Zone-3 personal-agent approvals.
- Moved smoke-test output to a repo-local `.agent-intake-smoke` folder and updated Power Pages URL examples.

## [0.1.0-preview] - 2026-05-02

### Added — Express-path MVP scaffolding

- **Manifest** — `manifest.yaml` registering the solution at `lifecycle-ops` domain, tier 3, controls 1.2/1.7/2.1/2.13/3.1
- **Dataverse schema** — `scripts/create_fsi_intake_dataverse_schema.py` defines 9 tables (`fsi_intakerequest`, `fsi_intakedatasource`, `fsi_intakerisksignal`, `fsi_intakereview`, `fsi_intakeapproval`, `fsi_intakedecisionlog`, `fsi_intakesponsorship`, `fsi_intakeauditevent`, `fsi_intakeretentionrecord`) and 7 global option sets, with `--output-docs` regenerating `docs/dataverse-schema.md`
- **Express form spec** — `docs/portal-configuration.md` documents the Power Pages Express form
- **Sponsor card** — `templates/sponsor-approval-card.json` Teams adaptive card with FINRA Rule 3110 attestation language
- **Flow build docs** — `docs/flow-configuration.md` step-by-step manual build instructions for the 3 Express-path flows (router, sponsor card, handoff). No exported flow JSON per repo Solution Content Policy.
- **Auto-detect playbook** — `docs/auto-detect-playbook.md` documents the verified Graph + PPAC endpoints used for pre-fill, and the manual fallbacks for Purview / retentionLabels
- **Auto-detect scripts** — `scripts/autodetect_environments.py`, `scripts/autodetect_dlp_simulation.py`, `scripts/autodetect_purview.py`
- **Classification rules** — `scripts/seed_classification_rules.py` seeds the Express-path tier/zone/retention auto-classification logic; `templates/policy-lookup-tables.yaml` carries the customer-overridable defaults
- **Handoff scripts** — `scripts/setup_entra_agent_id.py` (Microsoft Entra Agent ID handoff) and `scripts/setup_purview_retention_label.py` (one-time setup guidance for `FSI-AgentIntake-7yr` retention label)
- **Drift wiring** — `docs/drift-detection-integration.md` describes the integration points to `unrestricted-agent-sharing-detector`, `scope-drift-monitor`, `agent-access-monitor`, and `agent-365-lifecycle-governance`
- **Validation** — `scripts/smoke_test.ps1` end-to-end Express-path smoke test
- **Runbook** — `docs/pilot-deployment-runbook.md` step-by-step deployment + rollback procedures
- **Research artifacts** — `research/` carries the Phase A fit assessment, question-catalog evaluation, intake form design v1, API verification spike, and PO-resolved open questions (all from prior commits)
- **Adoption polish** — `docs/maker-quick-start.md`, `docs/sponsor-cheat-sheet.md`, `docs/onboarding-checklist.md`, `docs/decisions.md`, Mermaid architecture diagram added to README

### Out of scope — deferred

- **Standard path** (Tier-2/Zone-2, ~20 questions, InfoSec 10% sample dashboard) → planned for v0.3
- **Full path** (Tier-1/Zone-1, ~35 questions, parallel reviewer dashboard, MRM routing) → planned for v0.4
- **M365 Copilot declarative agent surface** (conversational intake) → planned for v0.4
- **Sovereign cloud adaptation** (GCC / GCC-High / DoD) → planned for v0.4
- **Localization** beyond en-US → post-v1.0

### Notes

- This is a **preview** release. Awaiting pilot-firm validation feedback before promoting to `live`.
- All defaults in `templates/policy-lookup-tables.yaml` are overridable per customer.
