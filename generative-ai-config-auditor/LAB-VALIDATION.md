# Lab Validation Report — Generative AI Config Auditor (GAC)

> **Original static validation date:** 2026-06-04
> **Live tenant validation date:** 2026-06-13 (see "Live tenant validation outcome — 2026-06-13" below)
> **Branch:** `validation/generative-ai-config-auditor`
> **Solution version:** v1.2.1 (fixes recorded under CHANGELOG `[Unreleased]`)
> **Validation type:** Static (parse-validity + authoritative-source verification + documentation completeness, 2026-06-04) **followed by live tenant validation of the bot-config-state detection path on the lab validation tenant (2026-06-13)**. The static report below is retained as the historical record; the live outcome is appended in its own dated section.

## Live tenant validation outcome — 2026-06-13

On 2026-06-13 the bot-config-STATE detection path was validated live against the lab validation tenant. This supersedes the "no live tenant was used" framing of the 2026-06-04 static report for the config-state path; the static report is retained below as the historical record.

**What was deployed.** The five `fsi_GAC*` Dataverse tables (baseline, validation history, violation, approved-connection, feature-inventory) with their columns, the two shared option sets (`fsi_acv_zone`, `fsi_acv_severity`) bound to the canonical live `100000000`-based members, and the three GAC-specific option sets. The schema deploy is idempotent (create-if-missing → reuse). The **deployed schema is the retained deliverable**; the disposable test fixtures described below were all removed afterward.

**What was proven against disposable-bot fixtures.** Detection was exercised end-to-end on throwaway bots authored with the real nested `bot.configuration` shape, with the real agents only read, never mutated:

- **Violation** — a fixture with `settings.GenerativeActionsEnabled = true`, `aISettings.useModelKnowledge = true`, and `aISettings.isSemanticSearchEnabled = true` on a Zone 1 (Enterprise) environment resolved to **Critical** with three rules firing (all three generative capabilities are prohibited at Zone 1).
- **Compliant** — a fixture with all three flags off produced **no** violation row.
- **Indeterminate (and the Rule 7 fix it exposed)** — a fixture with all three config-state nodes **absent** resolved each sub-check to "Unable to Determine". The live indeterminate run **exposed a comparator gap**: with no rule firing, the prior logic would have reported the bot **Compliant** — a false-Compliant on a bot whose posture is genuinely unknown. This was fixed by adding **Rule 7 (Indeterminate configuration, fail-closed)**: when all three config-state nodes are "Unable to Determine" and no other rule has fired, the detector now emits a `Warning` `IndeterminateConfiguration` violation rather than a silent Compliant. Rule 7 mirrors the Indeterminate handling already present in the CMM and FUS sibling solutions. The real-agent cross-check confirmed Rule 7 does **not** mis-flag normally-configured production agents.
- **Same-fixture flip + evidence integrity** — flipping the same fixture between the violation and compliant shapes flipped the detector result accordingly, and the **SHA-256 evidence digest (prefix `8D55C369`)** recomputed to an integrity match.

**Teardown verified.** After the proofs, the violation table returned from one row to zero, the three disposable bots were deleted (with their botcomponents), and the four GAC evidence tables were verified clean. **No disposable violation rows persist in the lab validation tenant.** The deployed schema remains as the deliverable.

**Honest framing.** This is **lab evidence** gathered from disposable-bot fixtures on the lab validation tenant — it demonstrates that GAC's config-state detection path works against the real Dataverse nested configuration shape. It is **not** a production guarantee: a customer's tenant evidence is produced by running the solution against the customer's own tenant, not by reading this report. Coverage remains **PARTIAL** — see "Known lab-scope limitation" below; the Work IQ usage-telemetry and Purview DLP legs remain out of lab scope (no connectors on the lab validation tenant), a scope boundary rather than an unrun check. This solution **supports compliance with** its named controls; it does not by itself ensure, guarantee, or eliminate regulatory risk.

## Purpose & Controls

The Generative AI Config Auditor validates that Copilot Studio agents comply with zone-specific generative AI governance policies — Azure OpenAI integration, generative orchestration, generative answers nodes, knowledge sources, **Allow ungrounded responses** (AI general knowledge), and **Work IQ** (semantic search).

- **Primary control:** 2.24 — Agent Feature Enablement Governance
- **Supporting:** 1.8 (Runtime Protection), 2.1 (Managed Environments / zone source), 3.8 (Copilot Hub / evidence export)
- **Regulatory context referenced by the solution:** FINRA Rule 3110(a)(1), SOX Section 404, GLBA Section 501(b); audit-trail tables support FINRA Rule 4511 / SEC Rule 17a-3/4 record-keeping.

## What Was Checked

| Area | Method | Result |
|------|--------|--------|
| PowerShell parse validity (all 14 `.ps1`) | `Parser::ParseFile` | 0 errors |
| Python compile (all 5 `.py`) | `python -m py_compile` | All OK |
| Token-acquisition correctness (Az.Accounts SecureString) | Source review + Microsoft Learn | **1 bug found & fixed** |
| Dataverse logical column names | Grep vs `create_dataverse_schema.py` | Consistent (no snake_case drift) |
| Entity-set names (incl. explicit-singular `fsi_gacvalidationhistory`) | Grep vs schema `entity_set_name` | Consistent |
| Option-set values (100000000+) | Schema vs docs | Consistent (no 0/1/2 drift) |
| Copilot Studio GenAI feature naming (current) | Microsoft Learn | All terms current |
| API permissions / required modules | Source review vs docs | **2 doc gaps fixed** |
| Flow Parse JSON schema vs runbook output | Source review | **2 mismatches fixed** |
| Regulatory language rules (prohibited overclaim phrases) | Grep (non-CHANGELOG `.md`) | 0 violations |

## Authoritative Sources Cited

1. `Get-AzAccessToken` default output type changed to `SecureString` — https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken (and "Protect secrets in Azure PowerShell" https://go.microsoft.com/fwlink/?linkid=2258844). Also confirmed `-ResourceUri` is an **alias** of `-ResourceUrl` (aliases: `Resource, ResourceUri`).
2. Copilot Studio **Allow ungrounded responses** and **generative orchestration** — https://learn.microsoft.com/microsoft-copilot-studio/advanced-generative-actions and Knowledge sources summary.
3. Copilot Studio **Turn on Work IQ** (semantic search) — https://learn.microsoft.com/microsoftsearch/semantic-index-for-copilot (referenced from the Generative AI settings page).
4. Tenant setting **Publish Copilots with AI features** — https://learn.microsoft.com/microsoft-copilot-studio/security-and-governance.
5. Microsoft Graph permission for `informationProtection/policy/labels` — `InformationProtectionPolicy.Read` (Delegated) / `InformationProtectionPolicy.Read.All` (Application): https://learn.microsoft.com/graph/api/informationprotectionpolicy-list-labels.
6. DLP for Microsoft 365 Copilot location — https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about (already cited in-script).

## Gaps Identified & Fixes Applied

### Scripts

1. **`scripts/private/Connect-EnvironmentDataverse.ps1` — SecureString token bug (functional, high impact).**
   The interactive `Get-AzAccessToken` path returned `$tokenResult.Token` directly. On Az.Accounts 5.x this property is a `SecureString`, so the downstream `Authorization: Bearer <token>` header rendered as the literal text `System.Security.SecureString`, causing `401 Unauthorized` on every per-environment and ELM Dataverse call made by `Get-AgentGenAISettings.ps1` (the core agent-enumeration script). Fixed by normalizing to plain text via `[System.Net.NetworkCredential]`, matching the pattern already present in `GACClient.psm1`, `Get-PurviewDLPEvidence.ps1`, and `Import-ApprovedAoaiConnections.ps1`. This was the one token-acquisition site missed when the SecureString fix was rolled out in v1.1.0/v1.2.1.

### Documentation

2. **`docs/prerequisites.md` — inaccurate Graph permission.** Replaced the "Microsoft Graph `Environment.Read.All` (Application)" row (no such Graph scope is used; `Get-AdminPowerAppEnvironment` uses the Power Platform Admin / BAP API governed by the admin roles already listed) with the Graph permission actually required by `Get-PurviewDLPEvidence.ps1`: `InformationProtectionPolicy.Read` / `.Read.All`.
3. **`docs/prerequisites.md` — missing module prerequisites.** Added `Microsoft.Graph.Authentication` (required by `Get-PurviewDLPEvidence.ps1`'s `#Requires` / `Invoke-MgGraphRequest`) and optional `ExchangeOnlineManagement`, with install commands.
4. **`docs/flow-configuration.md` — Parse JSON schema drift vs runbook output.** Violation items documented `Feature`/`ExpectedPolicy`/`ActualConfig` and `Drift.DriftDetected`, none of which `Start-GenAIConfigValidationRunbook.ps1` emits. Aligned the schema to the actual emitted fields: violation `AzureOpenAIEnabled`/`OrchestrationMode`/`GenerativeAnswersNodeCount`, and `Drift` = `HasDrift`/`IsFirstRun`/`DriftedAgents`/`Details`. (Power Automate Parse JSON tolerates non-required property differences, so this was a correctness/clarity fix rather than a hard runtime break.)

### Verified-correct (no change needed)

- GenAI feature terminology (Allow ungrounded responses, Work IQ, generative orchestration/answers) is current per Microsoft Learn.
- `-ResourceUri`/`-ResourceUrl` try/catch fallback is harmless — they are the same parameter (alias), so the pattern binds on any Az.Accounts version.
- Dataverse logical column names, entity-set names, and option-set integer values match `create_dataverse_schema.py`.
- The 3 evidence/runbook scripts (`Export-GenAIConfigEvidence.ps1`, `Invoke-GenAIBaselineCapture.ps1`, `Start-GenAIConfigValidationRunbook.ps1`) acquire tokens via MSAL.PS `.AccessToken` (plain text) — not affected by the Az SecureString change.

## Runtime-Only Caveats (cannot be verified without a live tenant)

- Actual Dataverse read/write against `bot`, `botcomponent`, `bot_botsettings`, and the five `fsi_GAC*` tables (auth, role assignment, table existence).
- `bot_botsettings` is an **optional extension table**; fall-through behavior when customers have not added platform-side `fsi_*` columns is by-design (per CHANGELOG 1.1.0) and only observable live.
- Power Platform environment enumeration behavior and zone classification via the shared `Get-ZoneClassification.ps1` module (external dependency at `scripts/shared/`).
- Microsoft Graph / Security & Compliance cmdlet availability and consent state for the Purview evidence script.
- `manifest.yaml` build verification (`build-manifest.py --check`) could not run in this worktree — it requires a sibling `fsi-agentgov` checkout providing `controls.json`. `manifest.yaml` was **not** modified, so no manifest drift is introduced.

## Lab-Readiness Assessment

**Ready for lab use, with the SecureString fix applied.** Before this change, the core enumeration path (`Get-AgentGenAISettings.ps1`) would have failed authentication on any host running Az.Accounts 5.x — a likely default in a fresh lab. With the fix plus the prerequisite/permission corrections, an operator following `docs/prerequisites.md` can install the correct modules, grant the correct permissions, and exercise the scan/baseline/evidence flows. The bot-config-state detection path has since been **live-validated against the lab validation tenant on 2026-06-13** (see "Live tenant validation outcome — 2026-06-13" above); the remaining out-of-scope items are the telemetry-dependent sub-checks recorded under "Known lab-scope limitation".

## OPTION A zone reconciliation (2026-06-13)

Per the accepted coordinator decision (Option A), the canonical zone semantics are:

| Integer | Canonical label | Sensitivity |
|---|---|---|
| 100000000 | Unclassified (fail-closed -> most-restrictive) | n/a |
| 100000001 | Zone 1 (Enterprise) | MOST restrictive / highest-risk |
| 100000002 | Zone 2 (Team) | middle |
| 100000003 | Zone 3 (Personal) | LEAST restrictive / lowest-risk |

GAC was authored against the inverted model (Zone 3 = Enterprise = strictest). It is reconciled under Option A so the strictest gen-AI policy attaches to Zone 1 and the canonical shared `fsi_acv_zone` integers are written:

- shared `scripts/shared/Get-ZoneClassification.ps1` naming map flipped (enterprise/prod -> Zone1, personal/dev/sandbox -> Zone3);
- `scripts/private/Get-ExpectedGenAIPolicy.ps1` policy bodies swapped (Zone 1 now ExplicitAllowlistOnly / Restricted / ModelKnowledge Disabled / Critical; Zone 3 now Allowed / Advisory / Warning);
- zone-to-integer maps canonicalized to 100000001/2/3 (`private/GACClient.psm1`, `Compare-GenAIConfigCompliance.ps1`, `private/Get-GACValidationResults.ps1`, `governance/Import-ApprovedAoaiConnections.ps1`);
- the SHARED `fsi_acv_zone` / `fsi_acv_severity` declarations in `scripts/create_dataverse_schema.py` reconciled to the live 100000000-based members (create-if-missing -> reuse, never recreate);
- whitelist enforcement now derives from the per-zone policy (`WhitelistEnforcement -eq 'Enforced'`) instead of a hardcoded inverted zone list;
- unit assertion `lab/tests/GacZoneCanonical.Tests.ps1` proves "strictest gen-AI policy = Zone 1 = 100000001" (10/10 pass).

The detector was also re-pathed to the live NESTED `bot.configuration` keys (Phase 0 probe): `settings.GenerativeActionsEnabled`, `aISettings.useModelKnowledge`, `aISettings.isSemanticSearchEnabled`; legacy flat keys remain as a fallback and a missing node stays 'Unable to Determine' (defensive — never a false Compliant).

`fsi_GACViolation.fsi_Severity` remains a free String (`Critical/High/Medium/Warning`) and is NOT bound to `fsi_acv_severity`, so no severity-bind fix is required (verified; mirrors CMM).

## Known lab-scope limitation

**Telemetry sub-checks are out of scope.** GAC's generative-AI config check is validatable on the lab validation tenant only for the **bot-config STATE** checks read from the Dataverse `bot` / `botcomponent` tables. Two sub-checks are **out of lab scope** because the lab tenant has no Purview / Work IQ connectors:

- **Purview DLP evidence** (`Get-PurviewDLPEvidence.ps1`) — needs a separate Microsoft Graph token + Dataverse token and DLP for Microsoft 365 Copilot policies.
- **Work IQ / semantic-search TELEMETRY** (usage signals) — only the config-state flag (`aISettings.isSemanticSearchEnabled`) is validatable; usage telemetry is not.

Lab validation is **not** gated on these telemetry legs. See `controls-covered.json` (`coverageScope.gaps`) and `AGENTS.md` -> "Out-of-lab-scope".
