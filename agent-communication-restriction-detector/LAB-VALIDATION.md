# Lab Validation Report — Agent Communication Restriction Detector (ACRD)

> **Validation type:** Static (no live tenant). Parse-validity + authoritative-source
> verification + documentation completeness.
> **Date:** 2026-06-04
> **Solution version:** v1.2.1
> **Primary control:** 2.17 — Multi-Agent Orchestration Limits
> **Supporting controls:** 1.8 (Runtime Protection), 2.1 (Managed Environments), 3.8 (Copilot Hub)

## Purpose

ACRD detects unauthorized agent-to-agent communication patterns, zone boundary
violations, cross-environment and cross-tenant communication, and maker/checker
violations in Copilot Studio multi-agent orchestration. It supports compliance with
FINRA Rule 3110, SOX 404, and GLBA 501(b) by producing auditable evidence of
agent communication topology and policy alignment.

## What was checked

| Area | Method | Result |
|------|--------|--------|
| Python compile | `python -m py_compile` on all 5 `scripts/*.py` | Pass |
| PowerShell parse | `Parser::ParseFile` on all 14 `.ps1`/`.psm1` | Pass (0 errors) |
| Dataverse column names | Cross-checked every OData `$select`/`$filter` against `create_dataverse_schema.py` | Logical names correct (e.g. `fsi_violationtype`, `fsi_validationtime`, `fsi_environmentsscanned`) |
| Option-set value drift | Compared `flow-configuration.md` and scripts against schema option sets | Correct — uses `100000000+` integers; no `0/1/2` drift |
| Entity set names | Verified `fsi_commscanrun` (singular, explicit) vs auto-plural sets | Consistent with schema `EntitySetName` |
| Schema docs sync | Compared `docs/dataverse-schema.md` against schema script | In sync |
| Language rules | Grep for prohibited phrases in `*.md`/scripts (excl. CHANGELOG history) | No violations |
| External API/feature claims | Verified against Microsoft Learn (see Sources) | 2 issues found and fixed |

## Authoritative sources cited

1. Get-MgPolicyCrossTenantAccessPolicyPartner (module Microsoft.Graph.Identity.SignIns) —
   https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/get-mgpolicycrosstenantaccesspolicypartner
2. crossTenantAccessPolicyConfigurationPartner resource (property shapes; `isServiceProvider`,
   `b2bCollaborationInbound`, `b2bDirectConnectInbound`, `inboundTrust`) —
   https://learn.microsoft.com/graph/api/resources/crosstenantaccesspolicyconfigurationpartner
3. crossTenantAccessPolicyB2BSetting (confirms B2B settings expose `usersAndGroups`/`applications`,
   not `isServiceProvider`) —
   https://learn.microsoft.com/graph/api/resources/crosstenantaccesspolicyb2bsetting
4. Copilot Studio quotas and limits (connector payload 5 MB / 450 KB GCC; Omnichannel 28 KB;
   Skills 100/agent) —
   https://learn.microsoft.com/microsoft-copilot-studio/requirements-quotas#copilot-studio-web-app-limits
5. Add a child agent (child agents have their own orchestration/tool limits) —
   https://learn.microsoft.com/microsoft-copilot-studio/add-agent-child-agent
6. Copilot component (botcomponent) table reference (Dataverse) —
   https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/botcomponent

## Gaps found and fixes applied

### Scripts

1. **Cross-tenant correlation read `isServiceProvider` off the wrong object (correctness bug).**
   `Get-CrossTenantAccessCorrelation.ps1` read
   `$partner.B2BCollaborationInbound.IsServiceProvider` /
   `$partner.B2BDirectConnectInbound.IsServiceProvider`. Per source (2)/(3),
   `isServiceProvider` is a property of the partner object; the B2B inbound members are
   `crossTenantAccessPolicyB2BSetting` objects without that property, so both expressions
   always evaluated to `$null`. **Fix:** read `IsServiceProvider` from the partner and
   record B2B collaboration / direct-connect inbound as presence checks; added a citation
   comment. Also documented the previously-undocumented `-IncludeCompliant` parameter.

2. **`Test-ChildAgentPayloadSize.ps1` cited a non-existent "documented 1 MB limit" and a dead URL.**
   The script asserted a "documented 1 MB Copilot Studio limit" for child-agent input/output and
   cited `microsoft-copilot-studio/advanced-flow-input-output`, which now redirects to generic
   agent-flow guidance with no byte limit. Per source (4), current published limits are a 5 MB
   connector payload (450 KB GCC) and a 28 KB Omnichannel channel-data limit — there is **no
   published child-agent input/output byte limit**. **Fix:** reframed the 1 MB value as a
   configurable advisory heuristic via a new `-PayloadLimitKB` parameter (default 1024), widened
   threshold validation ranges, updated finding text + `PlatformReference` URL, and corrected the
   README feature description. Behavior is unchanged at defaults.

### Documentation

3. **`docs/prerequisites.md` mislabeled MSAL.PS.** It listed MSAL.PS as "Evidence export
   authentication", but `Export-CommViolationEvidence.ps1` migrated to Az.Accounts in v1.2.1
   (CHANGELOG M-5). MSAL.PS is now used only by the Azure Automation runbook for certificate
   auth. **Fix:** corrected the purpose, flagged MSAL.PS as archived/runbook-only, and raised the
   Az.Accounts minimum to 2.17+ to match `Export-CommViolationEvidence.ps1` `#Requires`.

### Verified correct (no change needed)

- Dataverse OData queries use correct logical column names and entity set names.
- Power Automate option-set mappings use integer values `100000001`/`100000002` (Approved/Denied).
- Bot/skill discovery queries `bots` and `botcomponents`. Skill components are selected with
  `componenttype eq 1 or componenttype eq 13` (Skill / Skill (V2)) and joined to the owning bot
  via the `_parentbotid_value` lookup, consistent with the Dataverse botcomponent table (source 6).
  The second-pass review corrected an earlier `componenttype eq 2 or 10` (Bot variable / Bot
  translations (V2)) filter and a non-existent `_botid_value` column.
- Cross-tenant token-audience fix (C-1), `Get-Date -AsUTC` removal (C-2), and
  `Connect-EnvironmentDataverse` call-operator fix (C-3) from v1.2.1 remain correct.
- Sovereign-cloud Dataverse URL `ValidatePattern` regexes accept commercial + US Gov + Germany clouds.

## Runtime-only caveats (cannot be verified without a live tenant)

- **Payload-size estimation is heuristic.** `Test-ChildAgentPayloadSize.ps1` estimates payload size
  from botcomponent YAML byte counts; it does not measure actual runtime request/response sizes.
  Treat findings as advisory. Microsoft does not publish a child-agent byte limit, so the default
  threshold is a conservative organizational heuristic — tune `-PayloadLimitKB` to policy.
- **MSAL.PS is archived.** The runbook still depends on MSAL.PS for certificate auth. It functions
  today but receives no security updates; a future migration to `Get-AzAccessToken` (cert) or a
  managed identity is recommended. Left as-is to avoid an out-of-scope rewrite of the runbook auth.
- **`Get-CrossTenantAccessCorrelation.ps1` correlation** depends on tenant GUIDs being extractable
  from `fsi_calledenvironmentid`; per `.ralph-config.json`, explicit tenant-ID comparison is a
  URL/GUID heuristic and not yet a first-class tenant match. Behavior unchanged by this validation.
- Graph cmdlet return-object property names (PascalCased SDK projections) were validated against the
  Graph REST resource definitions; the live PowerShell SDK object graph was not exercised.

## Final lab-readiness assessment

**Lab-ready (static validation passed).** All scripts parse and compile; documentation is internally
consistent and matches the Dataverse schema; option-set and column references are correct; no
prohibited compliance language. Two authoritative-source defects (a Graph property-access bug and an
outdated/unverifiable platform-limit claim) were corrected. Remaining items are runtime-only caveats
that require a live tenant to exercise and are documented above. No `manifest.yaml` change was needed.
