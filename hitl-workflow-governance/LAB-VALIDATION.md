# Lab Validation — HITL Workflow Governance

**Solution:** hitl-workflow-governance · **Version:** v1.1.2 (Unreleased validation pass)
**Date:** 2026-06-04 · **Validation type:** Static (no live tenant) — parse-validity, authoritative-source verification, documentation completeness.
**Primary controls:** 2.12 (Supervision/FINRA Rule 3110), 2.17 (Multi-Agent Orchestration Limits), 1.10 (Communication Compliance). Supporting: 2.1, 3.8.

## Purpose

HITL Workflow Governance (HWG) scans Power Platform environments for Copilot Studio
agents and validates that their topics/flows include the required Human-in-the-Loop
checkpoints (**Request for Information** and **Run a Multistage Approval** from the
`shared_advancedapprovals` "Human in the loop" connector) per zone governance policy.
It persists evidence to three Dataverse tables and exports SHA-256-hashed evidence
packages for regulatory examination.

## What was checked

- All Python scripts compile (`python -m py_compile`).
- All PowerShell scripts/modules parse with zero errors (`Parser::ParseFile`).
- Anti-drift unit tests pass (`pytest` — 5 passed, 1 skipped).
- Dataverse column references against `create_hwg_dataverse_schema.py` and option-set
  values (100000000+ vs zero-indexed ordinals).
- Connector operation IDs, parameters, preview/GA status, and connector class against
  the authoritative Microsoft Learn connector reference.
- The Copilot Studio `botcomponent` `componenttype` filter values against the
  authoritative Dataverse entity reference.
- Token audiences and module dependencies (managed-identity-first; archived modules).
- Regulatory-language rules (the FSI prohibited-phrase list) — none found.

## Authoritative sources cited

| Source | URL |
|--------|-----|
| botcomponent (Copilot component) table reference — `componenttype` choices, `parentbotid` lookup, `statecode` | https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/botcomponent |
| Human in the loop connector reference — actions, operation IDs, parameters, class, preview status | https://learn.microsoft.com/en-us/connectors/advancedapprovals/ |
| Request information from human review (RFI doc) — GA Jan 30 2026, input types, parameters | https://learn.microsoft.com/en-us/microsoft-copilot-studio/flows-request-for-information |
| Multistage and AI approvals in agent flows (preview) | https://learn.microsoft.com/en-us/microsoft-copilot-studio/flows-advanced-approvals |
| Get-AzAccessToken (SecureString default, `-ResourceUrl`) | https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken |
| Power Platform / Dynamics 365 preview terms | https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/ |

## Gaps found and fixes

### 1. Wrong `botcomponent` componenttype filter (functional bug — fixed)

`Get-AgentHitlSettings.ps1` and `governance/Test-HitlCheckpointConfiguration.ps1`
filtered `componenttype eq 12 or componenttype eq 2` with an inline comment claiming
"12 = Topic, 2 = Dialog/Skill". The authoritative Dataverse reference
(`botcomponent_componenttype` global choice) defines:

| Value | Label |
|---|---|
| 0 | Topic |
| 1 | Skill |
| 2 | **Bot variable** |
| 4 | Dialog |
| 9 | Topic (V2) |
| 12 | **Bot variable (V2)** |

Values 12 and 2 are **Bot variable** components, which do not contain the topic/dialog
action and connector JSON the scan parses. The filter would skip the components that
actually hold HITL actions, so checkpoints could be silently missed (matching the
"No HITL Checkpoints Detected" symptom in `troubleshooting.md`).

**Fix:** filter now targets `componenttype eq 0` (Topic), `9` (Topic V2), `4` (Dialog),
and `1` (Skill) — the component types that carry action content across classic and V2
agents. Comments corrected to cite the Dataverse reference.

### 2. Archived MSAL.PS dependency in the runbook (deprecated module — migrated)

`Start-HitlValidationRunbook.ps1` required `MSAL.PS` (archived September 2023) and used
`Get-MsalToken` with a certificate for the Dataverse token. The rest of the solution
already migrated to `Az.Accounts` (council-review m-6) and demonstrates the pattern in
`private/Connect-EnvironmentDataverse.ps1`.

**Fix:** migrated the runbook to `Az.Accounts`
(`Connect-AzAccount -ServicePrincipal -CertificateThumbprint -ApplicationId -Tenant`
then `Get-AzAccessToken -ResourceUrl <DataverseUrl>`), with SecureString-to-string
conversion for the Az.Accounts 5.x default token type. The Dataverse token audience is
the environment URL (correct for the Dataverse Web API). Updated `#Requires`,
comment-based help, `docs/prerequisites.md`, and `docs/troubleshooting.md`; `MSAL.PS` is
no longer a dependency anywhere in the solution. A note recommends a system-assigned
managed identity (`Connect-AzAccount -Identity`) where supported.

### 3. Outdated "preview" status for Request for Information (doc accuracy — fixed)

The README, `prerequisites.md`, and `troubleshooting.md` described RFI as public preview.
Per the Power Platform release plan the RFI action reached **general availability on
January 30, 2026** (public preview began July 31, 2025). The connector reference page
still lag-labels the action "(preview)", and **Run a Multistage Approval** remains in
preview. Docs were updated to state RFI's GA milestone while preserving the accurate
caveat that the connector reference still tags it preview and that multistage approval
is preview — so the Power Platform preview-terms review guidance remains for the
multistage action.

### Verified correct (no change needed)

- RFI operation ID `RequestForInformation`; required params `title`, `message`
  (Outlook only), `assignedTo` (email) — matches the connector reference and
  `docs/flow-configuration.md` / `tests/test_connector_drift.py`.
- Multistage operation ID `StartAndWaitForAnApprovalProcess` (preview).
- Connector unique name `shared_advancedapprovals`, titled "Human in the loop",
  **Standard** class in Copilot Studio (the maker UI now groups these under a
  "Human review" category — cosmetic, connector identity unchanged).
- Reviewer list separator: semicolon (connector reference). The scan also splits on
  comma, which is harmless.
- Dataverse Web API version `v9.2`; option-set values (100000000+) consistent between
  schema generator, docs, and anti-drift tests.
- No prohibited regulatory-compliance language.

## Runtime-only caveats (require a live tenant to confirm)

1. **`botcomponents` lookup attribute (`_botid_value` vs `_parentbotid_value`).**
   The three scanning paths filter `botcomponents` by `_botid_value eq '<botid>'`.
   The authoritative Dataverse reference documents only a **`parentbotid`** lookup
   (OData `_parentbotid_value`) on `botcomponent` — there is no documented `botid`
   lookup. However, council-review fix **M-5** deliberately standardized all three
   scripts on `_botid_value` because that attribute matched the maintainers' production
   tenant and `_parentbotid_value` "can return zero rows in some tenants"
   (`.ralph-config.json`). This is a genuine documented-versus-deployed discrepancy that
   has varied across Copilot Studio platform versions. **This pass intentionally left
   `_botid_value` in place** to avoid reverting a tenant-tested fix without a live tenant
   to validate against. **Action for lab:** confirm in the target tenant which lookup
   attribute `botcomponents` exposes; if a query returns an OData "property not found"
   error or zero rows for an agent known to have topics, switch the filter to
   `_parentbotid_value` consistently across `Get-AgentHitlSettings.ps1`,
   `governance/Test-HitlCheckpointConfiguration.ps1`, and
   `private/HWGClient.psm1` (`Get-BotHitlSettings`).

2. **componenttype coverage.** The corrected filter (0/9/4/1) targets topic, dialog, and
   skill components. Confirm in the target tenant that the agents under test store their
   HITL-bearing topics as Topic (V2 = 9) — modern Copilot Studio agents do — and that no
   HITL actions live in component types outside this set.

3. **Regex-based action detection.** The scan parses `botcomponent.content` JSON with
   regular expressions for RFI/approval action and connector references. Connector schema
   may still change (RFI/multistage are GA/preview respectively). Re-validate detection
   patterns against a known agent with configured HITL actions after platform updates.

4. **Az.Accounts certificate sign-in.** The runbook migration was validated by static
   parse only. Confirm in Azure Automation that the certificate is present, the app
   registration has a Dataverse application user with read on `bot`/`botcomponent`, and
   that `Get-AzAccessToken -ResourceUrl <DataverseUrl>` returns a usable token.

## Final lab-readiness assessment

**Lab-ready with the caveats above.** All scripts parse, Python compiles, and unit tests
pass. The two corrected behaviors (componenttype filter, runbook auth) materially improve
the likelihood that a lab scan detects HITL checkpoints and authenticates without the
archived MSAL.PS module. The single most important pre-run check is **caveat 1** (the
`botcomponents` lookup attribute), which is tenant-version-dependent and cannot be
resolved statically. Documentation is complete and internally consistent; regulatory
language complies with FSI rules.
