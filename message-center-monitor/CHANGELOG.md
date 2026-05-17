# Changelog

## [Unreleased]

### Fixed
- `fsi_assessedby` column read as Lookup at 4 code sites (and described as Lookup in 2 comments) across `scripts/governance/Export-MessageCenterEvidence.ps1` and `scripts/governance/Get-MessageCenterAssessmentStatus.ps1`. The schema defines `fsi_AssessedBy` as a String column (`StringAttributeMetadata`, MaxLength 200); the `_fsi_assessedby_value` OData syntax that v2.4.0 introduced returns 400 Bad Request because that syntax is Lookup-only. Reverts the mistaken Lookup treatment introduced in v2.4.0 (see the correction note appended to the v2.4.0 entry below).
- `scripts/governance/Export-MessageCenterEvidence.ps1` output object previously exposed two fields (`assessedBy` mapped to the `_<col>_value@OData.Community.Display.V1.FormattedValue` annotation and `assessedById` mapped to `_<col>_value`) that were both modeled on Lookup semantics. Collapsed to a single `assessedBy` String field and removed the dead `_fsi_assessedby_value@OData.Community.Display.V1.FormattedValue` annotation block (the annotation never appears on a String column).

### Added
- `AGENTS.md` (this solution) — per-solution AI-agent context file. Establishes the per-solution `AGENTS.md` convention: when a solution has non-trivial in-flight work (active POC dry-run, customer handoff, multi-session refactor), it ships its own `AGENTS.md` that is **additive** to the root `AGENTS.md` / `CLAUDE.md` / `.github/copilot-instructions.md`. Carries the current operational state (phases done / pending), a cross-machine resume runbook, solution-specific conventions (a human-readable summary of `.ralph-config.json`), and AI-agent guardrails. Backfilling stable solutions is **not** required — opt-in per solution. Live IDs (tenant, env, app reg, KV) are intentionally NOT in this file — they live in `lab/lab-config.json` and `lab/lab-state.json`, both gitignored.
- `lab/Resume-LabState.ps1` — cross-machine bootstrap. Reads `lab/lab-config.json` for the resource NAMES (tenant id, app-reg display name, KV name, Power Platform env URL) and queries Microsoft Graph + Azure Resource Manager + BAP + Dataverse Web API to rediscover the derived GUIDs (`applicationId`, `objectId`, `servicePrincipalObjectId`, `secretKeyId`, KV `resourceId`, Power Platform `environmentId`, Dataverse `applicationUserId`, assigned role). Writes a complete `lab-state.json` so subsequent lab steps and `lab/99_Remove-LabDeployment.ps1` can run without re-provisioning. Read-only against cloud — never creates / modifies / deletes anything. Idempotent. Uses az CLI tokens for all auth (same pattern as the rest of the lab). Refuses to overwrite an existing `lab-state.json` without `-Force`.
- `lab/00b_New-PaygEnvironment.ps1` — fully-automated Power Platform sandbox env provisioning via an existing PAYG billing policy. Single `POST .../environments?api-version=2023-06-01` call combining `billingPolicy.id` + `databaseType=CommonDataService` + `linkedEnvironmentMetadata` in one body, which is the only known fully-automated path that bypasses the prepaid Dataverse pool capacity gate. Idempotent: re-runs find an existing env by `displayName` and only refresh `lab-config.json`. Dot-sources `lib/Write-LabLog.ps1`, honors `Assert-NonProdAcknowledgement`, redaction-safe. Confirmed working against the FSI test tenant with the `CopilotStudioAgentsBilling` policy in ~30 seconds end-to-end (env + Dataverse Ready + bound to policy).
- `lab/99_Remove-LabDeployment.ps1` `-RemoveEnvironment` switch — opt-in teardown of the env created by `00b_New-PaygEnvironment.ps1`. Off by default so a forgotten flag never wipes a shared lab env. Uses `DELETE .../scopes/admin/environments/{id}?api-version=2023-06-01` with the required `{"code":"User","message":"..."}` body.
- `lab/lab-config.example.json` — new `powerPlatform.displayName` and `powerPlatform.billingPolicyId` fields (both optional; auto-resolved if not set).
- `docs/poc-quickstart.md` Step 0b — instructions for the auto-provisioning path, gated on the customer having an existing PAYG billing policy. Documents the bypass mechanism (PAYG env-create vs prepaid pool) and the precondition that the policy's Power Platform products list must include Dataverse.
- `scripts/governance/Test-McmPrerequisites.ps1` — preflight script run before the first sync. 11 checks: PowerShell 7.2+, MSAL.PS and Az.KeyVault modules, Key Vault reachable, client secret present, Graph token, `ServiceMessage.Read.All` consent, Dataverse reachable, authorized read on `fsi_messagecenterlogs` (not just `$metadata`), alternate-key `fsi_MessageCenterIdKey` Active, Teams webhook URL (`-PostTestMessage` switch opts in to a real labeled test POST; default is dry-run only to avoid cluttering the channel), and **Phase 1 ⊕ Phase 3 mutual exclusion** (FAIL if both `$env:MCM_TEAMS_WEBHOOK_URL` is set and the Phase 3 flow's environment variable is deployed). Guards-compliant: dot-sources `_Common.ps1`; routes all HTTP through `Invoke-McmRest`; uses `Az.KeyVault` module (no `az` CLI).
- Teams Workflows incoming webhook posting in `scripts/governance/Invoke-MessageCenterSync.ps1`. Configurable via `-TeamsWebhookUrl` parameter or `$env:MCM_TEAMS_WEBHOOK_URL`; empty / unset disables Teams calls entirely. Idempotent per row via `fsi_notifiedon` (a sync re-run does not re-post). On a successful 200/202, the sync writes `fsi_notifiedon` via **direct PATCH** through `Invoke-McmRest` with a targeted single-field body — NOT through `Invoke-McmDvUpsertMessage`, which forbids admin-owned columns in its `$Record` parameter per the C1 invariant.
- `Send-McmTeamsWebhook` helper in `scripts/governance/_Common.ps1`. Loads the shared adaptive card template, walks the parsed object tree, substitutes `{token}` placeholders at the object level, wraps the result in the Teams Workflows `{type: message, attachments: [...]}` envelope, then `ConvertTo-Json -Depth 20`. Object-tree substitution (not naive `string.Replace` on raw JSON) is safe against double quotes, newlines, angle brackets, and Unicode in token values. Returns `{Success, Error}`; does not throw on HTTP failure so a single Teams outage cannot halt sync of the remaining messages.
- `Expand-McmCardTokens` helper in `scripts/governance/_Common.ps1` — the object-tree token expander that `Send-McmTeamsWebhook` is built on.
- `docs/poc-quickstart.md` — multi-phase POC runbook (Step 0 tooling bootstrap, Phase 1 customer POC bar, Phase 2 operationalization, Phase 3 Power Automate flow handoff, day-2 ops, troubleshooting decision tree, rollback). Includes a per-step role matrix, an at-a-glance Mermaid diagram, and an explicit alternate-key activation wait gate.
- `lab/07_Invoke-PocSmokeTest.ps1` — end-to-end POC smoke test mirroring the customer Phase 1 journey. 10 steps: preflight, alternate-key Active poll, local HTTP capture listener, sync 1, payload-shape assertion (`type=message`, `attachments[0].contentType=application/vnd.microsoft.card.adaptive`, `attachments[0].content.type=AdaptiveCard`), `fsi_notifiedon` populated assertion, sync 2, capture-count-unchanged assertion (per-row idempotency), `fsi_notifiedon` byte-identical assertion (C1 admin-column-preservation extended to the new write-back path), teardown. Includes listener-liveness probe POSTs between syncs to defeat false-pass on silent listener death.
- `lab/03_Deploy-Schema.ps1 -PocOnly` switch — skips the environment-variables and connection-references Python scripts (Phase 3 only) so the lab POC path matches the customer POC path exactly.
- `.ralph-config.json` — 17 verified domain facts that lock in column types, option-set value mappings (severity / category / assessment status), entity-set vs SchemaName, the 7 admin-owned columns, the C1 enforcement location, the direct-PATCH escape hatch, the adaptive card token contract, and the Phase 1 ⊕ Phase 3 mutual-exclusion rule. Future agents should read this before editing any script in this solution.
- `tests/AssessmentStatus.Query.Tests.ps1`, `tests/EvidenceExport.Query.Tests.ps1` — regression tests that assert the OData query shape (NOT a non-existent output schema, per the council critique on plan v1). They read the script source and assert that `fsi_assessedby` appears in `$selectFields`/`$select` and that `_fsi_assessedby_value` and `assessedById` do not appear anywhere.
- `tests/TeamsWebhook.Tests.ps1` — 26 tests covering `Expand-McmCardTokens` (object-level substitution; special-char round-trip safety for quotes, newlines, backslashes, angle brackets, Unicode) and `Send-McmTeamsWebhook` (envelope shape, retry on transient 5xx, no-throw contract on persistent 4xx and on DNS failure).
- `Format-McmSafeUri` helper in `scripts/governance/_Common.ps1` — redacts bearer-credential URLs (Teams Workflows / Logic Apps SAS / `*.webhook.office.com` / `*.azure-apim.net` / any URL with `sig=` or `code=` query parameter) to `<scheme>://<host>/<redacted>` BEFORE they reach any log sink. Dataverse and Microsoft Graph URLs pass through unchanged. Covered by 7 tests in `tests/Common.Tests.ps1`.
- `tests/Sync.Tests.ps1` AST-based invariant: every `Invoke-McmRest -Method PATCH` call has its `-Body` argument traced to the nearest hashtable assignment, and the keys are asserted to be a subset of the direct-PATCH allowlist (currently only `fsi_notifiedon`). Catches a future contributor adding another admin-owned column to the post-notify direct-PATCH body — which would bypass `Invoke-McmDvUpsertMessage`'s C1 guard and silently clobber every admin assessment on the next sync.

### Removed
- `scripts/ingest_service_health.py` — orphaned half-integration. Required `ServiceHealth.Read.All`, which `README.md` and `docs/setup-checklist.md` actively tell customers NOT to grant.
- `docs/graph-powershell-snippet.md` — companion to the removed script above.

### Changed
- `README.md` — added a top-of-doc fork between the **POC path** (Phase 1, the customer success bar), the **Operationalize path** (Phase 2, Status/Export/Assess), and the **Production flow path** (Phase 3, Power Automate). Each path points at its own runbook.
- `docs/flow-configuration.md` — added a Phase 3 banner at the top emphasizing that the Power Automate flow is **mutually exclusive** with the Phase 1 PowerShell webhook (run one, not both). Concrete `Remove-Item env:` step included for the migration.
- `templates/teams-notification-card.json` — updated `_comment` to document that the template is rendered by both the Phase 1 PowerShell sync (via `Send-McmTeamsWebhook`) and the Phase 3 Power Automate flow. Do not rename tokens or restructure the body without coordinating both paths.
- `scripts/governance/Invoke-MessageCenterSync.ps1` now exits non-zero when notification-path failures (`notifyFailedCount + notifyWriteBackFailedCount`) occur, not only when Dataverse upsert fails. A silent Teams or `fsi_notifiedon` regression in a scheduled run is the same severity as a silent Dataverse regression — a write-back failure causes the NEXT run to re-post the same alert, and Azure Automation / GitHub Actions / Logic Apps schedules need that signal to alert.
- `scripts/governance/Test-McmPrerequisites.ps1` check 10 (Teams webhook URL) now allows `http://localhost`-scheme URLs (downgrading the final result to WARN with an explicit loopback caveat) so the `lab/07` capture-listener path passes the same preflight gate the customer runs. Real `https://` external webhooks still PASS.
- `scripts/governance/Test-McmPrerequisites.ps1` check 11 (Phase 1 / Phase 3 mutual exclusion) now distinguishes a real Phase 3 deployment (env-var DEFINITION AND a bound VALUE) from a stale leftover from a prior `lab/03` run (DEFINITION exists, no VALUE bound). The latter downgrades from FAIL to WARN. A new `-AssumePhase1Only` switch bypasses Phase 3 detection entirely for Phase-1-only customers who want a clean PASS even with leftover scaffolding.
- `lab/07_Invoke-PocSmokeTest.ps1` wraps Steps 3-9 in a `try { ... } finally { ... }` block so the listener-job stop and capture-file deletion always run, even when `Add-Failure` throws. Without that, a single Step 4 abort would leak port 18765 and the capture file, FAILing the next `lab/07` run with "Address already in use".

### Security
- `scripts/governance/_Common.ps1` `Invoke-McmRest` no longer embeds the raw request URI in failure messages. The new `Format-McmSafeUri` helper rewrites Teams Workflows incoming webhook URLs, Logic Apps SAS URLs, `webhook.office.com` URLs, `*.azure-apim.net` URLs, and any URL with a `sig=` or `code=` query parameter to `<scheme>://<host>/<redacted>` BEFORE the message reaches any log sink. `scripts/governance/Test-McmPrerequisites.ps1` check 10 also stopped echoing `$TeamsWebhookUrl` in error `-Detail` strings — only the host name and HTTP status code are surfaced now. These webhook URLs are bearer credentials; the previous behavior leaked them into console output, scheduled-run logs, and any downstream Application Insights / Log Analytics pipeline on any transient failure.
- `scripts/governance/_Common.ps1` `Invoke-McmRest` also scrubs `sig=` and `code=` query parameter values from the **response error body** before appending it to the failure message (new `Format-McmSafeErrorBody` helper). Some APIs echo the original request URL inside their error body; without this scrub, the URI-redaction fix above would have been bypassed for any server that echoes the URL. Council round 3 defense-in-depth.

### Fixed (council round 3)
- `scripts/governance/Invoke-MessageCenterSync.ps1` `-OutputFormat Object` path no longer `return`s before the unified `exit 1` gate. For `pwsh -File script.ps1`, setting `$global:LASTEXITCODE = 1` does NOT propagate to the host process exit code; only an explicit `exit N` statement does. The previous code path silently exited 0 on notify failures when callers used `-OutputFormat Object`, defeating the round-2 fix for scheduled Object-format callers. New `Sync.Tests.ps1` AST regression test asserts the Object switch branch contains no `return` statement and that the unified `if ($terminalFailures -gt 0) { exit 1 }` gate is present at script scope.
- `scripts/governance/Test-McmPrerequisites.ps1` check 11 (Phase 1 / Phase 3 mutual exclusion) Dataverse query now selects `value` (not just `environmentvariablevalueid`) and filters with `IsNullOrWhiteSpace`. A bound-but-empty value row used to count as "Phase 3 active" and would FAIL on conflict; it now correctly downgrades to the WARN tier (stale leftover scaffolding).
- `scripts/governance/Test-McmPrerequisites.ps1` `-AssumePhase1Only` switch now returns **WARN** (not PASS) when Phase 1 is active. The previous PASS short-circuited the Dataverse query without warning; a customer who passed the switch in a misconfigured environment where Phase 3 was actually deployed would have seen a clean preflight and then duplicate Teams alerts on every sync. The WARN tier preserves the switch's purpose (skipping the Dataverse query) while making the incomplete check explicit to the operator.
- `tests/Sync.Tests.ps1` direct-PATCH body invariant test now enforces an **allowlist of exactly one** (`fsi_notifiedon`), not a blocklist of admin-owned columns. The blocklist would have passed a hypothetical future PATCH that added a non-admin column like `fsi_title`, contradicting the stated invariant ("the direct-PATCH path writes exactly one key").

No version bump — manifest stays at v2.5.1.

## [2.5.1] - 2026-05-04

### Changed
- Refreshed documentation against 2026-Q2 Microsoft Learn guidance for Graph service communications v1.0 endpoints, Message Center tags/services, and Power Automate connector naming.
- Updated the Teams adaptive card template and examples to Adaptive Card schema 1.5 while keeping connector-compatible `Action.OpenUrl` actions.
- Corrected shipped script metadata and comments to match the current Control 2.3-only mapping and Microsoft Entra ID branding.

### Fixed
- Replaced the legacy HTTP Premium connection reference with the current HTTP with Microsoft Entra ID connector (`shared_webcontents`) used for Microsoft Graph calls.
- Updated stale solution version metadata in README and evidence export output.

## [2.5.0] - 2026-04-30

### Added
- **Lab dry-run automation** (`lab/`) — numbered idempotent PowerShell scripts that bootstrap a complete non-prod deployment and exercise the v2.4.0 fix end-to-end against a live Power Platform environment.
  - `00_Install-Prereqs.ps1` — installs PS modules + pip packages; verifies runtimes; optional `-CheckRoles` for directory role check.
  - `01_New-AppRegistration.ps1` — creates app reg + SP, resolves Graph `ServiceMessage.Read.All` AppRole and Dataverse `user_impersonation` scope **dynamically** (no hardcoded GUIDs), admin-consents, polls for consent confirmation, rotates client secret only when no existing credential is valid for ≥30 days. `-ForceRotate` to mint a new secret unconditionally. Cross-process secret handoff uses a gitignored, owner-ACL'd `lab/.secret-handoff` file (consumed and deleted by 02); when a Key Vault is already recorded in `lab-state.json`, the rotated secret is also pushed to KV directly so 02 becomes optional.
  - `02_New-KeyVault.ps1` — RBAC-mode Key Vault with `Key Vault Secrets User` role for the runner; reads + deletes the `.secret-handoff` file written by 01 (env-var handoff was unreliable across pwsh process boundaries). Never logs the secret value.
  - `03_Deploy-Schema.ps1` — wraps the 3 Python setup scripts; **polls `EntityDefinitions.../Keys` for `EntityKeyIndexStatus = Active` for up to 15 min** (configurable) before returning success.
  - `04_New-AppUser.ps1` — Dataverse Application User + role association (`FSI Message Center Sync` with `System Customizer` lab fallback) + **effective-access probe with retry**. Probe re-acquires the SP token before each attempt so the role just granted is reflected in the token claims.
  - `05_Set-EnvVarValues.ps1` — populates the **6 `fsi_MCM_*` environment variable definitions** (`PollingIntervalDays`, `NotifySeverities`, `TeamsTeamId`, `TeamsChannelId`, `DataverseUrl`, `KeyVaultSecretName`) from `lab-config.json`.
  - `06_Invoke-LabSmokeTest.ps1` — **the dry-run.** 10-step orchestrator: unit tests → DryRun sync → live sync → idempotent re-sync (asserts `UpdatedRecords ≥ 1`, `FailedRecords == 0`, `NewRecords == 0` parsed from sync output) → flip ALL 7 admin-owned columns on a row → back-date `fsi_lastupdated` and re-sync (asserts the C1 update branch actually fired AND all 7 admin columns are byte-identical) → assessment status → evidence export → integrity verify → manual cloud-flow gate.
  - `99_Remove-LabDeployment.ps1` — state-driven idempotent teardown that refuses to touch resources not in `lab-state.json` unless `-ForceExternalResource`. Removes the same 6 `fsi_MCM_*` env-var definitions that 05 created.
  - `lib/Write-LabLog.ps1` — shared logger that scrubs Bearer tokens, `client_secret`, `Authorization` headers, `access_token`, `refresh_token` from every log line. Also exports `Assert-NonProdAcknowledgement` and the `.secret-handoff` helpers.
  - `lab-config.example.json` — fill-in template; `lab-state.schema.json` — JSON-Schema for the ownership manifest; `.gitignore` excludes config + state + handoff + logs.
- **Non-prod safety guard**: every mutating lab script (`01`-`06`, `99`) calls `Assert-NonProdAcknowledgement` before any side-effect. The guard requires `lab-config.json` to contain the literal string `"I understand this lab must not target production"` in `nonProd.acknowledgement` (case + punctuation sensitive). An explicit `-AllowProduction` switch on each script bypasses the guard with a loud warning, intended only for deliberate prod re-validation.
- **`docs/lab-dry-run.md`** — engineer runbook with prereqs, execution order, **council-finding-to-test traceability matrix**, and a troubleshooting tree.
- **README "Lab dry-run" section** linking to the runbook above the Quick Start.

### Changed
- Manifest bumped to `2.5.0`. No control or prerequisite changes.

## [2.4.0] - 2026-04-30

### Added
- **Mock-based test suite** (`tests/`) — Pester (PowerShell) and pytest (Python) coverage for the high-risk surfaces introduced in this release. Hard-gated in CI on every PR; no tenant required.
  - `Upsert.Tests.ps1`: 8 cases for `Invoke-McmDvUpsertMessage` covering create→412→update branching with set-intersection JSON-body assertions on all 7 admin-owned columns (the C1 regression class).
  - `Common.Tests.ps1`: formatters, `Invoke-McmRest` retry on 429/5xx with `Retry-After` parsing (H2/H3), `Get-McmAccessToken` auth-mode dispatch (H1), and secret-redaction helper.
  - `Sync.Tests.ps1`: orchestration counter math + refactor wiring guards.
  - `Guards.Tests.ps1`: every HTTP-using governance script dot-sources `_Common.ps1`; no direct `Invoke-RestMethod` outside the helper; no `az` CLI.
  - `test_schema.py`: `create_keys()` payload shape, idempotency on 412/`DuplicateRecord`, and `--dry-run` honoring.
- **`Invoke-McmDvUpsertMessage` helper** in `_Common.ps1` — encapsulates the conditional create-with-`If-None-Match: *` → 412 → update branching so it can be unit-tested in isolation. Caller's `$Record` hashtable is never mutated; admin-owned columns are added only to a clone for the create payload.
- **`Write-McmRedacted` helper** in `_Common.ps1` — scrubs Bearer tokens, `client_secret`, and `Authorization` headers from log lines.
- Alternate key `fsi_MessageCenterIdKey` on `fsi_messagecenterid` provisioned by `create_mcm_dataverse_schema.py` — enables idempotent upsert via `PATCH .../fsi_messagecenterlogs(fsi_messagecenterid='MCxxxxx')`.
- `-AuthMode` parameter on all 3 PowerShell governance scripts (`ManagedIdentity` default, plus `WorkloadIdentity`, `Interactive`, `DeviceCode`, and `ClientSecret` legacy fallback).
- `SupportsShouldProcess` (`-WhatIf`/`-Confirm`) on `Invoke-MessageCenterSync.ps1`.
- Shared `_Common.ps1` helper module: retry-with-backoff REST helper, token cache with refresh-near-expiry, OData URL escape utilities.
- `--update`/`--force` flag on `create_mcm_connection_references.py`.
- `--log-level` argument on all 3 Python setup scripts; structured logging via the `logging` module.
- Setup checklist Step 6: explicit Dataverse Application User creation.
- Setup checklist Step 12: smoke test via `Invoke-MessageCenterSync.ps1 -DryRun`.
- Conditional Access guidance for the service principal in README and setup checklist.
- Secret rotation cadence guidance (90 days production, ≤365 days non-production) in `docs/secrets-management.md`.
- 2026-03-31 Office 365 Connectors retirement callout in `docs/teams-integration.md`.
- HTML sanitization security note for the `fsi_body` field in README and `docs/teams-integration.md`.
- Per-solution STRIDE threat model entry in repo root `THREAT-MODEL.md`.

### Changed
- **Critical:** Rewrote `docs/setup-checklist.md` end-to-end against the v2.3.0+ schema-script deployment path. The previous v2.2.0 manual-table flow contradicted the README and would have produced a broken deployment under any non-`fsi_` publisher prefix.
- **High:** All customer-facing docs reordered to recommend certificate / federated credential as the primary auth path; client secret marked as legacy fallback. Aligns with the repository's managed-identity-first authentication standard.
- **High:** `Invoke-MessageCenterSync.ps1` replaced SELECT-then-POST/PATCH with a single-call alternate-key upsert. Eliminates the read-then-write race condition and halves API calls per record.
- **High:** `Get-MessageCenterAssessmentStatus.ps1` and `Export-MessageCenterEvidence.ps1` now use the shared retry/backoff helper for all Dataverse calls (previously only the Sync script honored throttling).
- **High:** `docs/flow-configuration.md` field-mapping table now uses Dataverse logical names (`fsi_*`) and adds previously-omitted columns: `fsi_enddatetime`, `fsi_tags`, `fsi_hasattachments`, default `fsi_assessmentstatus = 100000000`.
- **Medium:** `create_mcm_environment_variables.py` `type_code` mapping replaced with an explicit dict (`String/Number/Boolean/JSON/DataSource/Secret`) keyed by exact label.
- Pinned upper bounds in `requirements.txt` (`msal<2.0`, `requests<3.0`).
- Token cache now refreshes within 5 minutes of expiry so long-running syncs no longer 401 mid-loop.
- All pagination loops now request `Prefer: odata.maxpagesize=500` and abort safely after 1000 pages.
- Severity values now displayed as labels (High/Normal/Critical) in `Get-MessageCenterAssessmentStatus.ps1` output, matching `Export-MessageCenterEvidence.ps1`.
- `Test-EvidenceIntegrity.ps1 -Quiet` now returns `$false` instead of throwing, honoring the documented `.OUTPUTS Boolean` contract.
- Hash and JSON files written by `Export-MessageCenterEvidence.ps1` now use UTF-8 without BOM (compatible with `sha256sum -c`).
- Adaptive card `$schema` URL upgraded to `https://`; `[bracket]` placeholders replaced with `{curly}` tokens that Power Automate substitutes.
- Manifest control mapping reduced to `2.3` only — Control 2.10 (Patch Management) was an aspirational stretch; this solution does not patch anything.
- Manifest prerequisites expanded to include `azure-admin` (Key Vault) and `teams-admin` (channel owner).
- README header version updated to 2.4.0; status changed to "Live" to match the manifest enum.

### Fixed
- **Critical:** Setup checklist no longer instructs admins to manually create the Dataverse table with display-label columns and text option values, which contradicted the v2.3.0 README and broke every governance script.
- **Critical:** Setup checklist now includes the Dataverse Application User step (previously documented only in the README and missing from the canonical checklist).
- **High:** `docs/flow-configuration.md` OData filter changed from `messagecenterid eq …` (would fail at runtime) to `fsi_messagecenterid eq …`.
- **High:** Removed regulatory citations (FINRA Rule 4511(a), SEC Rule 17a-4, SOX 302/404) from `Export-MessageCenterEvidence.ps1` and `Test-EvidenceIntegrity.ps1`. The README explicitly disclaims compliance/audit scope; prior CHANGELOG entries had stripped these claims and they had drifted back in.
- **High:** Repaired corrupt markdown table cell at `teams-integration.md:89`; resolved self-contradictory publisher-prefix note at `teams-integration.md:332`; removed multiple empty `> **Note:**` placeholders.
- **Medium:** `Export-MessageCenterEvidence.ps1` `$select` changed from `fsi_assessedby` (returned null) to `_fsi_assessedby_value` with FormattedValue annotation for Lookup column display.
  > _Correction ([Unreleased]): the Lookup treatment described here was a mistake — `fsi_assessedby` is a String column (`StringAttributeMetadata`, MaxLength 200), not a Lookup, so the `_fsi_assessedby_value` syntax returns 400 Bad Request. See the `[Unreleased]` "Fixed" entry above for the revert._
- **Medium:** OData literals (`$messageId`, dates) now URL-encoded and apostrophe-escaped to prevent filter injection.
- **Medium:** `[ValidateRange(1, 365)]` on `DaysBack` parameters prevents zero/negative values producing empty windows or excessive ranges that hit Graph throttling.
- Removed unused `from typing import Optional` imports (ruff would flag).
- Wrapped `--output-docs` write with `try/except OSError` for clear permission-error messages.
- Setup script `getpass` prompt now skipped in `--dry-run` mode.
- Setup scripts now mirror the shared client's exit-code taxonomy (1/2/4).
- All triple-backtick code blocks now have language tags for MkDocs Material syntax highlighting.
- Replaced `Write-Host` operational banners with `Write-Information -InformationAction Continue` (suppressible in CI).
- "Microsoft Entra tenant ID" wording now consistent across all 3 setup scripts.

### Removed
- Control mapping `2.10` (Patch Management) — solution does not patch anything.

### Security
- Customer-facing docs no longer prescribe client secret as the recommended auth path; certificate-based / federated credential is now the primary recommendation. Aligns with the repository's managed-identity-first authentication standard.
- Added per-solution STRIDE threat model entry in repo root `THREAT-MODEL.md`.
- `docs/secrets-management.md` adds 90-day rotation cadence for production tenants.
- README and `docs/teams-integration.md` add an HTML sanitization warning for the `fsi_body` field (raw HTML from Microsoft Graph).

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
