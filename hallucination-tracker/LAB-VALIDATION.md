# Lab Validation — Hallucination Feedback Tracker

> **Solution:** hallucination-tracker · **Version:** v1.2.0 · **Validation date:** 2026-06-04
> **Mode:** Static validation (no live tenant). Parse-validity + authoritative-source verification + documentation completeness.

## Purpose and controls

Feedback aggregation pipeline that normalizes hallucination signals (Copilot Studio
reactions/comments, Microsoft 365 Copilot Product Feedback, supervisor rejections,
automated groundedness checks, customer complaints) into the `fsi_hallucinationreports`
Dataverse table and reports category / agent / topic / channel / time-window clusters.

Primary controls: **3.10** (Hallucination Feedback Loop), **2.9** (Performance Monitoring),
**2.12** (Supervision — FINRA Rule 3110). Supports — but does not on its own satisfy —
FINRA Rule 2210, SEC Rule 206(4)-1, and CFPB chatbot guidance.

## What was checked

| Area | Method | Result |
|------|--------|--------|
| Python syntax (7 files) | `python -m py_compile` | Pass |
| Python unit tests | `pytest` (analyzer + importer suites) | 48 passed |
| Analyzer dry run | `analyze_patterns.py --dry-run --format json` | Pass |
| PowerShell parse (3 files) | `Parser::ParseFile` | 0 errors |
| Dataverse column references | Cross-checked every `fsi_*` token in scripts/docs against `create_ht_dataverse_schema.py` | No mismatches |
| Option-set values | Verified docs use `100000000+` (not `0/1/2`) for category/severity/source | Consistent |
| Regulatory language rules | Grep for the four prohibited overclaim phrases from `fsi-language-rules.instructions.md` (excl. CHANGELOG) | 0 hits |
| Authentication standard | Reviewed all auth paths | Managed-identity-first; client secret marked dev-only legacy |
| External feature/API claims | Microsoft Learn verification (below) | All confirmed |

### Column-naming verification

All referenced columns resolve to valid logical names from the schema script
(`fsi_category`, `fsi_severity`, `fsi_agentid`, `fsi_source`, `fsi_topicname`,
`fsi_topicid`, `fsi_channelid`, `fsi_feedbackcomment`, `fsi_groundednessdetected`,
`fsi_reportedat`, `fsi_isresolved`, `fsi_hallucinationreportid`, `createdon`, `modifiedon`,
etc.). The non-column `fsi_*` tokens flagged during scanning are the plural entity-set name
(`fsi_hallucinationreports`), option-set names (`fsi_ht_category/severity/source`),
environment-variable schema names (`fsi_ht_*`), and connection-reference names
(`fsi_cr_*`) — all legitimate, not column references.

### Authentication review

- `analyze_patterns.py` uses a managed-identity-first `ChainedTokenCredential`
  (ManagedIdentity → WorkloadIdentity → AzureCli → AzurePowerShell), with the
  client-secret path explicitly marked `# legacy: dev-only` and gated behind warnings.
- The Dataverse token scope is the environment `.../.default` (correct audience for the
  Dataverse Web API), not a Graph scope.
- PowerShell governance scripts use MSAL.PS interactive (admin-workstation) or a legacy
  client-secret service principal; `$ClientSecret` is typed `[SecureString]` and passed to
  `Get-MsalToken -ClientSecret` correctly. No `Get-AzAccessToken` SecureString hazard exists
  (these scripts do not use Az.Accounts). Managed identity is not wired into the PowerShell
  path, which is acceptable for the documented interactive admin-workstation use case.

## Authoritative sources cited

| Claim verified | Source URL |
|----------------|------------|
| Reactions On by default; **Settings > User feedback > Collect user reactions to agent messages**; M365 Copilot channel doesn't support reactions; Bot Transcript Viewer needed to view comments; Effectiveness > Reactions | https://learn.microsoft.com/microsoft-copilot-studio/analytics-improve-agent-effectiveness |
| Reaction / Comment / CSAT definitions; drill down to reactions and comments | https://learn.microsoft.com/microsoft-copilot-studio/analytics-questions-sessions |
| Session transcript CSV fields (`SessionID`, `TopicName`, `TopicId`, `ChannelId`, `CSAT`, `Comments`); 512-character per-response `ChatTranscript` truncation; download of past 29 days; Bot Transcript Viewer role | https://learn.microsoft.com/microsoft-copilot-studio/analytics-transcripts-studio |
| Comments available in the Analytics page for **28 days**; feedback/comments also in the Dataverse conversation transcript table | https://learn.microsoft.com/microsoft-copilot-studio/analytics-questions-sessions |
| Graph `aiInteractionHistory: getAllEnterpriseInteractions` requires `AiEnterpriseInteraction.Read.All`; covers M365 apps (Teams/Word/Outlook); **does not retrieve interactions in agents created by Copilot Studio** | https://learn.microsoft.com/microsoft-365/copilot/extensibility/api/ai-services/interaction-export/aiinteractionhistory-getallenterpriseinteractions |
| Azure AI Content Safety Groundedness detection is **preview**; response field `ungroundedDetected` (Boolean), `ungroundedPercentage` | https://learn.microsoft.com/azure/ai-services/content-safety/quickstart-groundedness |
| Administrators view/export organizational feedback in **Microsoft 365 admin center > Health > Product Feedback**; Copilot feedback collected via thumbs up/down in M365 apps | https://learn.microsoft.com/microsoft-365/copilot/employee-self-service/feedback · https://learn.microsoft.com/microsoft-365/admin/manage/manage-feedback-ms-org |

Every external feature, table/field name, permission, token audience, and availability/naming
statement in the README and `docs/` was matched against the sources above and found accurate,
including the documented preview status of groundedness detection and the Graph-API caveat
that it does not cover Copilot Studio agents.

## Gaps and fixes

No code, schema, column-naming, option-set, language-rule, auth, or token-audience defects
were found. Scripts and documentation are internally consistent and align with current
Microsoft Learn guidance. No repairs were required during this validation pass.

Minor (no change made): `docs/prerequisites.md` already notes that exporting Microsoft 365
Product Feedback uses "least-privilege roles documented by Microsoft 365 admin center."
Microsoft Learn specifies that any administrator/reader can view and export feedback, while
the Purview Compliance Admin (or Entra Global Admin) role is additionally required to perform
compliance tasks and see poster identity. The existing wording is accurate; no edit applied.

## Runtime-only caveats (cannot be verified statically)

- Live Dataverse schema deployment, application-user provisioning, and table read/write
  permissions require a tenant to confirm.
- Managed-identity, workload-identity-federation, and MSAL.PS interactive token acquisition
  depend on tenant identity configuration.
- Microsoft 365 Product Feedback availability depends on tenant feedback policy
  (`Allow users to provide feedback to improve Copilot experiences`).
- Copilot Studio reaction/transcript availability and 28-/29-day retention windows depend on
  environment transcript-recording settings being enabled.
- Azure AI Content Safety Groundedness detection is a preview API; region, API version, and
  data-handling terms should be revalidated before any production use.
- The Power BI dashboard template is planned for a future release (documented limitation).

## Lab-readiness assessment

**Lab-ready.** All static checks pass (7/7 Python files compile, 48/48 tests pass, 3/3
PowerShell files parse cleanly), there are no column-name or option-set discrepancies, no
prohibited compliance-language phrases, and authentication follows the managed-identity-first
standard. Every documented external dependency and API behavior is confirmed against
authoritative Microsoft Learn sources. Remaining items are runtime/tenant-dependent
validations and the already-documented future-release dashboard, none of which block lab use.
