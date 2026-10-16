# Prerequisites Technical Verification - 2026-10-16

**Last Verified:** 2026-10-16

**Scope:** Microsoft product facts in the ACA v1.2.3 prerequisites and their local
downstream guidance. Live Microsoft Learn search/fetch and local source inspection
were used. No tenant, credentials, GitHub authentication state, or remote writes
were accessed. Regulatory text, mappings, and coverage judgments were not changed.
This is documentation verification, not new live deployment evidence.

## Discrepancies and corrections

| Claim | Verified correction and propagation | Microsoft source |
|---|---|---|
| E5/E5 Compliance provides mandatory tenant-wide agent/action visibility | Removed the blanket core-scan prerequisite. The implementation reads Power Platform/Dataverse configuration, not Graph application inventory. Dataverse S2S application users do not need a paid user license, but the environment, capacity, requests, and agent authoring still have their own entitlements. Optional Purview licensing is feature-specific, not an E5-only rule. Updated prerequisites, README, flow guide, and the ACA-specific deployment-guide clarification. | [Dataverse S2S][s2s], [Copilot Studio licensing][copilot], [Audit Standard/Premium][audit], [Purview licensing][purview-license] |
| Premium license required for every scanner/flow creator | Distinguished script-only scanning from premium-connector flows. Both Dataverse and Azure Automation are premium connectors in Power Automate. Premium user licensing and an allocated Process license are documented alternatives, subject to the actual ownership/use model. | [Power Automate licenses][flow-license], [Dataverse connector][dv-connector], [Automation connector][automation-connector] |
| Application Administrator is needed to register the app | Registration depends on tenant policy; ordinary permitted users or Application Developer can register applications. Kept application creation separate from consent and runtime authorization. | [Register application][register], [Delegate application roles][app-roles] |
| Graph `Application.Read.All`, delegated Dynamics CRM `user_impersonation`, and admin consent collectively authorize the daemon | Core scripts do not make Graph inventory calls. Power Platform management-application registration and an authenticated administration session are separate from Dataverse S2S application users/security roles in each environment. Delegated impersonation does not authorize a certificate daemon. Updated setup, checklist, troubleshooting, and runbook help. | [Management applications][management-app], [Single-tenant S2S][single-tenant], [Application users][app-users], [Database security][security] |
| MSAL.PS handles runbook certificate tokens; Az.Accounts is workstation-only | The shipped certificate wrapper requires Az.Accounts 5.0.0+ and uses `Connect-AzAccount -ServicePrincipal -CertificateThumbprint` and `Get-AzAccessToken`. Its exporter also uses Az.Accounts. The version minimum is the local `#Requires` contract, not an asserted Microsoft-wide minimum. | [Noninteractive authentication][az-auth], [Get-AzAccessToken][token]; local runbook/exporter source |
| Uploading a certificate and publishing the wrapper completes unattended setup | Public certificate registration and the matching worker private key are distinct. Automation assets are retrieved with `Get-AutomationCertificate`; thumbprint sign-in uses the local personal store. The wrapper signs into Az but does not call `Add-PowerAppsAccount`, while the detector calls `Get-AdminPowerAppEnvironment`. Added worker bootstrap, dependency-layout, certificate/private-key, and known-agent coverage gates rather than asserting that deployment already works. | [Automation certificates][certificates], [Noninteractive authentication][az-auth], [Administration PowerShell][admin-powershell]; local wrapper/detector/helper source |
| Same-region placement is a requirement | Labeled co-location as a deployment choice. No ACA API same-region requirement was established. | [Automation security/accounts][automation-security] |
| AI Hub/DSPM setup implies complete Copilot activity correlation | Current branding is Data Security Posture Management, replacing the earlier classic experiences. The optional helper requires PowerShell 7+, unlike the core scanner. Its Graph filters select information-protection records; `Get-ActivityExplorerData` is a separately supplied fallback, not the documented `Export-ActivityExplorerData`. Added explicit incomplete-collection, query-completion, and paging boundaries to prerequisites, README, troubleshooting, script help, and the historical lab report. | [Current DSPM][dspm], [Classic prerequisites][dspm-classic], [Copilot Studio/Purview][purview-copilot], [Activity Explorer export][activity], [Create audit query][create-query] |
| `AuditLogsQuery.Read.All` is the only API permission | Confirmed that the broad permission is accepted for both query creation and record retrieval, delegated or application; service-scoped alternatives also exist. The example retains this broad delegated scope and requires consent. Creating a query is a POST that creates a query object, despite the permission's Read name. | [Create audit query][create-query], [Read query records][read-records] |
| Get job output polls job status; connector and runbook identities are interchangeable | Corrected the flow guide to use **Get status of job** and retrieve output after successful completion. The Azure Automation connector's managed-identity authentication is documented for Logic Apps, not Power Automate. The Power Automate OAuth connection and runbook identity are separate. | [Automation connector][automation-connector], [Runbook execution/status][job-status] |

## Claims retained and boundaries

- **Runtime:** Microsoft still documents the administration module as .NET
  Framework/Windows PowerShell 5.x, incompatible with PowerShell 6+. Retained the
  Windows PowerShell 5.1 scanner path. Automation runtime/package associations
  must match the actual worker; PowerShell 7+ support elsewhere does not remove
  this module restriction. Sources: [installation][install], [runtime][runtime].
- **Registration:** Entra ID > App registrations > New registration, single-tenant
  selection, client/tenant IDs, and no daemon redirect URI remain valid. The ACA
  name and parameter names are local conventions. Sources: [registration][register],
  [single-tenant S2S][single-tenant].
- **Roles:** System Administrator/System Customizer are sufficient broad setup
  roles, not claimed minimum runtime roles. Custom scan roles need the actual
  operations and privilege depths. Local inspection confirmed reads of `bot`,
  `botcomponent`, environment-variable definitions/values, and exceptions, plus
  evidence writes. Tenant roles alone do not grant these data permissions.
  Sources: [database security][security], [application users][app-users],
  [Agent table][bot], [Agent component table][botcomponent].
- **Network:** Retained HTTPS 443 and the commercial Entra, regional Dataverse,
  Azure management, and BAP examples. Marked them non-exhaustive and added optional
  Graph egress. Hybrid workers/connectors may need additional endpoints. Sources:
  [Power Platform required services][network], [Automation networking][automation-network].
- **Tokens:** Retained separate Graph and Dataverse audiences and the
  Dataverse-audience SecureString token input/Az fallback, verified against local
  helper code and [Get-AzAccessToken][token]. Direct token acquisition is not an
  overall environment/licensing exemption.
- **Local contracts:** Checked the schema command/`--interactive`, three custom
  tables/logical names, parameter names, runbook dependencies, and ELM wrapper.
  Shared ELM/naming classification and `Unknown`/Zone 1 semantics are local policy,
  not Microsoft product behavior; they were not changed. No prerequisite
  screenshots are present.
- **Unvalidated runtime:** No fresh Automation job, certificate-store import,
  management-identity handoff, complete environment scan, flow execution, or
  Purview query was run. The MI sample has a different output envelope; its
  Power Apps token handoff remains unproven. Optional Purview SKU availability,
  audit privileges, supported channel/data configuration, and complete record
  ingestion must be verified for the adopter's scenario. Existing lab dates and
  control coverage remain unchanged.

## Downstream artifacts reviewed

Paths are repository-relative. Unchanged means no propagation of these
prerequisite corrections was needed, not a new audit of every unrelated statement.

| Artifact | Outcome and reason |
|---|---|
| `action-confirmation-auditor/docs/prerequisites.md` | Changed: factual corrections, source citations, complete deployment/optional checklist distinction, current version and verification date. |
| `action-confirmation-auditor/README.md` | Changed: repeated licensing, role/runtime requirements and Purview evidence claims; added verification-record link. The README's whole-solution/live-validation date was not advanced. |
| `action-confirmation-auditor/docs/flow-configuration.md` | Changed: dependency/bootstrap prerequisites, job-status action, connector identity distinction, known-agent/evidence acceptance checks, and authentication/zero-result/Purview troubleshooting. |
| `action-confirmation-auditor/LAB-VALIDATION.md` | Changed: dated clarification supersedes old setup/collection assumptions without rewriting historical observations or claiming new tenant results. |
| `action-confirmation-auditor/CHANGELOG.md` | Changed: new Unreleased entry. Prior verification and implementation history retained. No release/version bump. |
| `action-confirmation-auditor/docs/technical-verification-2026-10-16.md` | Added: this source/discrepancy/downstream/validation record. |
| `action-confirmation-auditor/scripts/Start-ActionConfirmationValidationRunbook.ps1`, `scripts/Start-ActionConfirmationRunbook-MI.ps1`, `scripts/Get-PurviewAIHubEvidence.ps1` | Changed **help comments only**: synchronized dependencies, authorization/identity boundaries, non-drop-in MI contract, and optional collection caveat. Executable-token comparison confirmed no executable changes. |
| `action-confirmation-auditor/docs/dataverse-schema.md` | Regenerated; changed: shared option-set prose now matches the schema generator's existing output. No table/column/choice definition changed. |
| `action-confirmation-auditor/manifest.yaml`, `controls-covered.json` | Manifest unchanged; coverage export regenerated unchanged. Catalog prerequisites do not restate the corrected E5/MSAL/Graph requirements. Authored coverage rationale and regulatory text were not reinterpreted. |
| `action-confirmation-auditor/.ralph-config.json` | Unchanged: schema names/entity sets, expiration semantics, and Windows PowerShell compatibility remain applicable. |
| `action-confirmation-auditor/scripts/create_dataverse_schema.py`, `create_environment_variables.py`, `create_connection_references.py`, `deploy.py`, `aca_client.py`, `requirements.txt` | Unchanged: local schema, setup interfaces, connector IDs and Python dependencies are unaffected. The schema generator ran offline only. |
| `action-confirmation-auditor/scripts/Get-AgentActionSettings.ps1`, `Test-ActionConfirmationCompliance.ps1`, `private/ACAClient.psm1`, `private/Connect-EnvironmentDataverse.ps1`, `private/Get-ZoneClassification.ps1`, `private/Get-ExpectedConfirmationPolicy.ps1`, `private/Test-ParameterValidation.ps1` | Unchanged: inspected authentication call sites, resource operations, classification/dependencies and output contracts. Documented the missing wrapper administration-session bootstrap rather than changing runtime behavior during this verification task. |
| `action-confirmation-auditor/scripts/Export-ActionAuditEvidence.ps1`, `Test-EvidenceIntegrity.ps1`, `governance/Test-UserDefinedActionMessages.ps1`, `governance/Import-ActionRiskClassifications.ps1` | Unchanged: exporter already uses Az.Accounts; hash checks, per-zone detection and deferred risk-import behavior do not depend on the removed E5/Graph/MSAL prerequisites. |
| `action-confirmation-auditor/tests/TopicV2Detection.Tests.ps1` | Unchanged: offline detector/helper/pagination/fail-closed contracts; 35 tests pass. No live setup or complete Purview collection is implied. |
| `scripts/shared/Get-ZoneClassification.ps1` | Unchanged: shared fallback and canonical naming policy are unrelated to licensing/authentication corrections. |
| `DEPLOYMENT-GUIDE.md` | Changed: ACA-only licensing clarification avoids assigning the author license requirement to the S2S scanner. Other catalog/regulatory rows untouched. |
| `hitl-workflow-governance/README.md` | Unchanged: linked comparison distinguishes reviewer checkpoints from end-user confirmation; none of the corrected prerequisites are repeated. |
| `scripts/README.md`, `scripts/Invoke-CopilotStudioBenchmark.ps1` | Unchanged: discovered benchmark references do not restate E5/MSAL/Graph prerequisites. Existing control labels were deliberately not remapped in this technical-only task. |
| `scripts/_backfill-zones.py`, `scripts/lint-odata-existence.py`, `scripts/tests/test_build_manifest_partial_controls.py` | Unchanged: zone defaults, schema discovery, and preserved partial-coverage tests do not rely on corrected setup claims. |
| Root `README.md`, `AGENTS.md`, `.github/copilot-instructions.md`, root `CHANGELOG.md`, `.squad/skills/repo-context.md` | Unchanged: catalog/context/history references, without corrected prerequisite details. No catalog version update required. |
| `solutions.json`, `site-docs/solutions/index.md`, `site-docs/reference/control-mapping.md`, `site-docs/index.md`, all solution `controls-covered.json` exports | Regenerated unchanged using CI-pinned framework v1.6.0; no catalog schema/version/mapping/metrics change or stored prerequisite verification date. |
| `site-docs/getting-started/deployment-guide.md` | Regenerated; changed to mirror the ACA licensing clarification in its source. |
| `site-docs/solutions/action-confirmation-auditor/index.md`, `prerequisites.md`, `flow-configuration.md`, `dataverse-schema.md`, `technical-verification-2026-10-16.md` | Regenerated gitignored outputs: index discovers the new sub-doc; sub-docs mirror source corrections and verification metadata. No hand edits to these generated paths. |
| `site-docs/reference/changelog.md`, other solution detail pages/sub-docs | Regenerated; unrelated content unchanged. The solution README and lab report are not copied verbatim into manifest-derived overviews. |
| `mkdocs.yml` | Changed: added the technical verification page under ACA; existing prerequisite/flow/schema navigation retained. |
| `scripts/build-manifest.py`, `scripts/manifest.schema.json`, `scripts/controls-covered.schema.json` | Unchanged: existing generator links/discovers sub-docs. No content-graph generator exists here. |

The source's local implementation, troubleshooting, validation checklist and
evidence instructions were reviewed through the artifacts above. External
framework control links are regulatory references, not an additional ACA setup
playbook; they were not reinterpreted. No companion-repository changes are claimed.

## Regeneration and local validation

Use the same controls input as CI: the published framework **v1.6.0**
`assessment/manifest/controls.json`, through `FRAMEWORK_CONTROLS`. The adjacent
development checkout has 79 controls and produced unrelated two-file baseline
drift; it was not used for committed regeneration. The CI-pinned 78-control input
passed the tracked-artifact baseline check.

Commands run from the repository root:

```powershell
python action-confirmation-auditor\scripts\create_dataverse_schema.py --output-docs
python scripts\build-manifest.py
python scripts\build-manifest.py --check
python -m mkdocs build --strict
python -m pytest scripts\tests\ -q
Import-Module Pester -RequiredVersion 5.7.1
Invoke-Pester -Path .\action-confirmation-auditor\tests\TopicV2Detection.Tests.ps1
python scripts\lint-odata-columns.py
python scripts\lint-odata-existence.py
python scripts\validate-language-rules.py
python scripts\verify_commercial_scope.py
python scripts\sync-agent-md-versions.py --check
python scripts\lint-version-drift.py --strict
python scripts\lint-optionset-values.py --strict
python -m ruff check .
```

Shared Python regressions: **114 passed**. ACA offline Pester: **35 passed**.
Manifest consistency, strict MkDocs build, language/scope checks, version/choice
contracts, Python lint, and OData column checks passed. OData existence checking
exited 0 with **17 pre-existing advisory findings outside ACA**; none were fixed
or represented as new regressions. Strict MkDocs retained pre-existing INFO-level
navigation/anchor notices outside ACA. Help-only PowerShell edits parse and retain
the baseline executable tokens (normalizing BOM/line endings for comparison).
No complete hosted CI run or live tenant success is claimed.

## Sources

All linked Microsoft sources were retrieved live using Microsoft Learn tools on
2026-10-16. License and runtime conclusions are limited to the components described
above; they are not a tenant-specific entitlement determination.

| Area | Live primary sources |
|---|---|
| Licensing | [Power Automate][flow-license], [Dataverse connector][dv-connector], [Automation connector][automation-connector], [Copilot Studio][copilot], [Audit capabilities][audit], [Purview service description][purview-license] |
| Identity and roles | [App registration][register], [Application roles][app-roles], [Management applications][management-app], [Dataverse S2S][s2s], [Single-tenant setup][single-tenant], [Application users][app-users], [Database security][security], [Agent table][bot], [Agent component table][botcomponent] |
| Runtime and tokens | [Administration PowerShell][admin-powershell], [Module installation][install], [Automation runtime][runtime], [Az authentication][az-auth], [Access tokens][token], [Certificate assets][certificates], [Automation security/accounts][automation-security] |
| Network and job monitoring | [Power Platform required services][network], [Automation networking][automation-network], [Runbook execution/status][job-status] |
| Optional activity correlation | [Current DSPM][dspm], [Classic prerequisites][dspm-classic], [Copilot Studio/Purview][purview-copilot], [Create audit query][create-query], [Read audit records][read-records], [Activity Explorer export][activity] |

[s2s]: https://learn.microsoft.com/power-apps/developer/data-platform/build-web-applications-server-server-s2s-authentication
[single-tenant]: https://learn.microsoft.com/power-apps/developer/data-platform/use-single-tenant-server-server-authentication
[copilot]: https://learn.microsoft.com/microsoft-copilot-studio/requirements-licensing
[audit]: https://learn.microsoft.com/purview/audit-solutions-overview
[purview-license]: https://learn.microsoft.com/office365/servicedescriptions/microsoft-365-service-descriptions/microsoft-365-tenantlevel-services-licensing-guidance/microsoft-purview-service-description
[flow-license]: https://learn.microsoft.com/power-platform/admin/power-automate-licensing/types
[dv-connector]: https://learn.microsoft.com/connectors/commondataserviceforapps/
[automation-connector]: https://learn.microsoft.com/connectors/azureautomation/
[register]: https://learn.microsoft.com/entra/identity-platform/quickstart-register-app
[app-roles]: https://learn.microsoft.com/entra/identity/role-based-access-control/delegate-app-roles
[management-app]: https://learn.microsoft.com/power-platform/admin/powershell-create-service-principal
[app-users]: https://learn.microsoft.com/power-platform/admin/manage-application-users
[security]: https://learn.microsoft.com/power-platform/admin/database-security
[az-auth]: https://learn.microsoft.com/powershell/azure/authenticate-noninteractive
[token]: https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken
[certificates]: https://learn.microsoft.com/azure/automation/shared-resources/certificates
[admin-powershell]: https://learn.microsoft.com/power-platform/admin/powershell-getting-started
[automation-security]: https://learn.microsoft.com/azure/automation/automation-security-overview
[dspm]: https://learn.microsoft.com/purview/data-security-posture-management-learn-about
[dspm-classic]: https://learn.microsoft.com/purview/dspm-for-ai-considerations
[purview-copilot]: https://learn.microsoft.com/purview/ai-copilot-studio
[activity]: https://learn.microsoft.com/powershell/module/exchangepowershell/export-activityexplorerdata
[create-query]: https://learn.microsoft.com/graph/api/security-auditcoreroot-post-auditlogqueries?view=graph-rest-1.0
[read-records]: https://learn.microsoft.com/graph/api/security-auditlogquery-list-records?view=graph-rest-1.0
[install]: https://learn.microsoft.com/power-platform/admin/powershell-installation
[runtime]: https://learn.microsoft.com/azure/automation/runtime-environment-overview
[network]: https://learn.microsoft.com/power-apps/maker/canvas-apps/limits-and-config
[automation-network]: https://learn.microsoft.com/azure/automation/automation-network-configuration
[job-status]: https://learn.microsoft.com/azure/automation/automation-runbook-execution
[bot]: https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot
[botcomponent]: https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/botcomponent
