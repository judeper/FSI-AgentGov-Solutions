# Lab Validation Report — Agent Registry Automation

> Static validation performed without a live tenant. Scope: parse-validity,
> authoritative-source verification of every documented API/permission/endpoint,
> and documentation completeness. Validated June 2026 against Microsoft Learn.

## Solution purpose and controls

Automated discovery, registration, approval, and lifecycle governance of AI
agents across Power Platform. Version 2.1.1. Primary controls: **1.2** (Agent
Registry and Integrated Apps Management), **1.7** (Comprehensive Audit Logging),
**2.1** (Managed Environments), **2.13** (Documentation and Record Keeping).
Supports compliance with FINRA Rule 4511, SEC Rule 17a-3/4, OCC Bulletin
2011-12, Fed SR 11-7, and GLBA 501(b). No single control satisfies a regulation
in isolation.

## What was checked

- PowerShell parse-validity (`Parser::ParseFile`) on both `.ps1` scripts — 0 errors.
- Python `py_compile` on all five `.py` scripts — pass.
- Every Dataverse column / entity-set reference in scripts and docs against the
  canonical schema in `scripts/create_dataverse_schema.py` and the generated
  `docs/dataverse-schema.md` (logical names, option-set values 100000000+).
- Every documented API endpoint, API version, auth audience, and permission name
  against authoritative Microsoft sources.
- Managed-identity-first auth patterns and correct token audiences per service.
- FSI regulatory language rules across edited Markdown.

## Authoritative sources cited

| Topic | Source URL |
|-------|-----------|
| Power Platform REST API reference (namespaces; AppManagement = Microsoft-provided application packages) | https://learn.microsoft.com/rest/api/power-platform/ |
| BAP "List environments" (admin) — `api.bap.microsoft.com/.../scopes/admin/environments?api-version=2020-10-01` | https://learn.microsoft.com/rest/api/power-platform/ |
| Power Platform programmability authentication — scopes `https://api.powerplatform.com/.default` and `https://service.powerapps.com//.default` | https://learn.microsoft.com/power-platform/admin/programmability-authentication |
| Dataverse `bot` (Copilot) table — EntitySetName `bots`, PK `botid`, PrimaryName `name`, no `botFrameworkEndpoint` column | https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot |
| Copilot Studio Agent Inventory (`bot`/`botcomponent` Dataverse tables) | https://learn.microsoft.com/microsoft-copilot-studio/guidance/kit-agent-inventory-data-source |
| `ILinkedEnvironmentMetadata.instanceUrl` (environment Dataverse org URL) | https://learn.microsoft.com/javascript/api/@microsoft/powerapps/ilinkedenvironmentmetadata |
| Cross-environment Dataverse connector usage | https://learn.microsoft.com/power-automate/dataverse/connect-other-environments |

## Gaps found and fixes applied

### 1. Fabricated "Bots API" discovery surface (High) — fixed

The discovery design used `https://api.powerplatform.com/appmanagement/environments/{id}/bots?api-version=2022-03-01-preview`.
The Power Platform REST API reference scopes the **AppManagement** namespace to
"managing installation for Microsoft-provided application packages in Dataverse"
— it has no `/bots` route. The authoritative agent inventory is the Dataverse
`bot` table. The CHANGELOG shows this path was previously guessed twice
(`/powervirtualagents/.../bots` → `/appmanagement/.../bots`) and never verified.

**Fix:** `Deploy-AgentRegistry-Baseline.ps1` and `docs/flow-configuration.md`
(Flow 1) now:
- Enumerate environments via the BAP admin API (`scopes/admin/environments?api-version=2020-10-01`).
- Read agents from each environment's Dataverse `bot` table (`GET {instanceUrl}/api/data/v9.2/bots`),
  mapping `botid` → `fsi_agentid` and `name` → `fsi_agentname`.

### 2. Non-existent `botFrameworkEndpoint` column (High) — fixed

`properties.botFrameworkEndpoint` was mapped to `fsi_agentendpointurl`. The `bot`
table has no such column. **Fix:** mapping removed; `fsi_agentendpointurl` is left
blank during discovery, with a note to populate from channel config if required.

### 3. Wrong/missing token audiences (Medium) — fixed

The script acquired a single `https://api.powerplatform.com` token for both
environment listing and bot reads. **Fix:** BAP enumeration uses audience
`https://service.powerapps.com/`; per-environment `bot`-table reads use a token
whose audience is that environment's `instanceUrl`. Tokens are cached per
instance URL. Acquisition remains managed-identity-first via
`Get-AzAccessToken -ResourceUrl`.

### 4. Fabricated permission names (Medium) — fixed

`docs/prerequisites.md` / `docs/troubleshooting.md` listed `Bot.Read.All` and
`Environment.Read.All` as Power Platform API application permissions. These are
not documented. **Fix:** environment enumeration is authorized by the **Power
Platform Admin** role; agent discovery requires a Dataverse security role with
read on the `bot` table in each scanned environment. Microsoft Graph permissions
(`User.Read.All`, `Directory.Read.All`, `AuditLog.Read.All`) for Flow 4 are
retained and verified as Graph application permissions requiring admin consent.

### 5. Documentation coherence (Minor) — fixed

Network endpoint list (`api.bap.microsoft.com` replaces `api.powerplatform.com`),
connection-reference descriptions, README architecture diagram, Known
Limitations, Platform Update Notes, and the `fsi_agentsource` future-enhancement
wording were aligned to the corrected mechanism. The HTTP-with-Entra-ID
connector note now flags that one connection authenticates against one resource
URI, so separate connections are needed for the BAP (`service.powerapps.com`) and
Graph (`graph.microsoft.com`) audiences.

## Items verified as already correct

- All Dataverse logical column names and entity-set names match the schema script.
- Option-set values use 100000000+ (not 0/1/2) consistently in scripts and docs.
- `Test-AgentRegistryCompliance.ps1` uses correct entity sets, logical names,
  managed-identity auth, and correct per-service token audiences (Dataverse vs
  Graph). No changes required.
- Python deployment scripts are Dataverse-only, managed-identity-first, with the
  legacy client-secret path properly marked as a dev-only fallback.
- Flow 3 (Entra Agent ID) is feature-flagged off and already carries appropriate
  preview caveats — left unchanged.

## Runtime-only caveats (cannot be confirmed without a live tenant)

- The owner-expand path on the `bot` table (`owninguser.domainname` /
  `internalemailaddress`) and the `statecode` semantics should be confirmed
  against the live table; column availability can vary by Dataverse version.
- The exact JSON path `properties.linkedEnvironmentMetadata.instanceUrl` in the
  BAP admin environments response should be confirmed against a live response;
  the field is documented on `ILinkedEnvironmentMetadata` but the admin REST
  payload shape is version-dependent.
- Cross-environment `bot`-table reads require the runtime identity to hold a
  read-capable Dataverse role in every scanned environment — verify per tenant.
- Microsoft Entra Agent ID (Flow 3) remains preview; endpoints and permission
  names must be confirmed in-tenant before enabling.

## Lab-readiness assessment

**Ready for lab deployment with documented runtime verification.** The discovery
pipeline now targets only authoritative, documented Microsoft APIs, with correct
token audiences and accurate prerequisites. Scripts parse cleanly and Python
compiles. The remaining unknowns are runtime-only (exact response field paths,
per-environment role assignments) and are explicitly flagged above for
confirmation during the first lab run. A maintainer version bump (suggested
`2.2.0`) plus the standard catalog/manifest sync is recommended as a follow-up.

## Second-Pass Command-Existence Re-Verification (2026-06-05)

An independent second-pass audit re-derived every invoked command, cmdlet, CLI verb, REST endpoint and api-version, Dataverse entity set / logical column / option-set, and module against Microsoft Learn, with a sharpened focus on confirming each surface exists and will run in a live lab. The BAP admin environments route with api-version 2020-10-01 and token audience, the Dataverse bot table (no botFrameworkEndpoint column), pac copilot list, Get-AzAccessToken, and Microsoft Graph v1.0 signInActivity were confirmed; the pass-1 BAP correction holds. Two runtime-only items (Entra Agent ID beta preview, live response shapes) are caveated.

