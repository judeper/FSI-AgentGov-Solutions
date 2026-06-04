# Lab Validation Report — Generative AI Config Auditor (GAC)

> **Validation date:** 2026-06-04
> **Branch:** `validation/generative-ai-config-auditor`
> **Solution version:** v1.2.1 (fixes recorded under CHANGELOG `[Unreleased]`)
> **Validation type:** Static — parse-validity + authoritative-source verification + documentation completeness. No live tenant was used.

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

**Ready for lab use, with the SecureString fix applied.** Before this change, the core enumeration path (`Get-AgentGenAISettings.ps1`) would have failed authentication on any host running Az.Accounts 5.x — a likely default in a fresh lab. With the fix plus the prerequisite/permission corrections, an operator following `docs/prerequisites.md` can install the correct modules, grant the correct permissions, and exercise the scan/baseline/evidence flows. Live functional execution against a tenant remains the only outstanding verification and is outside the scope of this static validation.
