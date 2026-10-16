# Troubleshooting technical verification - 2026-10-16

## Scope and method

Re-verified `deny-event-correlation-report/docs/troubleshooting.md` against live
Microsoft Learn `microsoft_docs_search` / `microsoft_docs_fetch` and Microsoft
Release Communications. This is a product-documentation review, not a compliance
assessment or a new tenant validation. Regulatory wording, control mappings,
coverage, release versions, and runtime classification logic were not changed.
No screenshots were present in the source guide.

A separate research-capable agent checked Microsoft claims; repository tracing
reviewed the dependent implementation and evidence surfaces. The important
adversarial finding is that a successful extraction or empty CSV cannot validate
an undocumented event schema. Runtime corrections based solely on a broad
substring search would introduce a different, unvalidated classifier, so this
change instead adds an explicit production-validation gate at every relevant
surface.

## Claims checked and discrepancies

| Surface | Finding and disposition |
|---|---|
| Audit enablement | **Corrected:** run `Get-AdminAuditLogConfig` in Exchange Online PowerShell. Security & Compliance PowerShell always returns False for this ingestion property [S1]. |
| Audit roles and availability | **Corrected:** name Exchange Audit Logs / View-Only Audit Logs roles and distinguish app permissions from cmdlet RBAC. Replace the blanket 24-hour delay with workload-dependent availability; the typical 60-90 minutes for core services is not a Copilot SLA [S2]. |
| Record type and basic search | **Retained, qualified:** `CopilotInteraction` is record type 261; other AI activities have different streams. The ten-record diagnostic is a connectivity sample, not completeness evidence [S3-S5]. |
| Audit pagination and performance | **Corrected:** 5,000 is a page size, not total coverage. Use a stable session with `ReturnLargeSet`, continue until exhausted, and split saturated 50,000-result windows. Use `UserIds` for UPN filtering. No documented early-morning UTC speed advantage was found [S5]. |
| Application Insights retirement | **Confirmed:** Release Communications explicitly extends query API-key retirement to September 30, 2026. The Learn lifecycle table still lists March 31; the specific extension notice resolves the chronology conflict. Passing the announced date is not an observed shutdown test [S6-S7]. Removed the obsolete API-key diagnostic rather than encouraging key troubleshooting. |
| Entra query authentication | **Retained, clarified:** `https://api.applicationinsights.io` is the token audience and query endpoint. Distinguish the Insights Application ID from instrumentation key and app client ID. Monitoring Reader supports reading monitoring data; assign Azure RBAC to the identity/service principal on the resource, not to an app registration [S8-S9]. URL-encode GET KQL. |
| Token/runtime contract | **Retained:** Az.Accounts 5.0 defaults to SecureString. Explicitly require PowerShell 7+ for `ConvertFrom-SecureString -AsPlainText`; remove unnecessary historical opt-in-version precision from the diagnostic [S10-S12]. |
| RAI discovery/schema | **Corrected:** Microsoft searches the custom-dimensions bag for `ContentFiltered`; it does not establish the exact `MicrosoftCopilotStudio` event name, `EventType` predicate, or `BotId`, `BotName`, `FilterReason`, `FilterCategory`, `FilterSeverity` keys used by this solution. The diagnostic now inspects raw dimensions; the production predicates remain tenant-validation assumptions, not asserted Microsoft contracts [S13-S15]. |
| Telemetry configuration, publication, delay | **Corrected:** test-canvas telemetry is documented, so publishing is not a universal prerequisite. Check connection string, logging configuration, and possible data-policy blocking at the documented settings path. Replace fixed 5-10-minute timing with variable ingestion delay. Input or output filtering can trigger the error [S13-S16]. |
| Blob access | **Retained, qualified:** Storage Blob Data Contributor and `UseConnectedAccount` are appropriate. Container listing tests read/list access, not upload. Use a new name rather than disabling immutable protection. Automation is not covered by the storage trusted-services exception [S17-S19]. |
| Power BI refresh | **Corrected and propagated:** use semantic model/settings/Refresh terminology, connection-owned credential maintenance, and Desktop schema refresh/republish. Key rotation applies only to account-key connections [S20-S22]. |
| Large exports | **Qualified:** ZIP is an archival copy unless ingestion/decompression is implemented; CSV incremental refresh needs `RangeStart`/`RangeEnd` and effective date/file pruning. Cold is online; Archive requires rehydration before reading [S23-S25]. Local symptom sizes/durations are not product limits. |
| Exchange connections and Conditional Access | **Retained, qualified:** managed-identity and certificate command patterns are documented, but need app permission/consent/effective roles. Thumbprint authentication is Windows-only. **Corrected:** workload-identity Conditional Access excludes managed identities and has licensing/supported-principal constraints [S26-S28]. |
| Graph audit search | **Retained:** `/security/auditLog/queries` is documented on v1.0, with `AuditLogsQuery.Read.All` or applicable workload-specific permissions. The non-beta SDK cmdlet is in `Microsoft.Graph.Security`, with beta equivalents in `Microsoft.Graph.Beta.Security`; no migration was performed [S29-S31]. |
| Automation diagnostics | **Corrected:** published jobs need verbose logging enabled in runbook settings before starting. Describe job streams rather than assuming fixed portal tab labels [S32]. |
| Trace diagnostic | **Corrected:** Warning is severity 2, Error is 3. The query now includes Warning and above and is labeled application-trace inspection, not proof of ingestion health [S33]. |

## Sources

All Learn sources were checked live. They establish product documentation, not
tenant configuration, end-to-end completeness, or regulatory outcomes.

| ID | Primary source |
|---|---|
| S1 | [Turn auditing on or off](https://learn.microsoft.com/purview/audit-log-enable-disable) |
| S2 | [Search the audit log](https://learn.microsoft.com/purview/audit-search) |
| S3 | [Management Activity API record types](https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-schema#auditlogrecordtype) |
| S4 | [Audit logs for Copilot and AI applications](https://learn.microsoft.com/purview/audit-copilot) |
| S5 | [Search-UnifiedAuditLog](https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog) |
| S6 | [Microsoft retirement extension notice](https://www.microsoft.com/releasecommunications/api/v2/Azure/rss/transition-to-azure-ad-to-query-data-from-azure-monitor-application-insights-by-31-march-2026) |
| S7 | [Lifecycle: ending support in 2026](https://learn.microsoft.com/lifecycle/end-of-support/end-of-support-2026) |
| S8 | [Application Insights Entra query authentication](https://learn.microsoft.com/azure/azure-monitor/app/azure-ad-authentication#query-application-insights-by-using-microsoft-entra-authentication) |
| S9 | [Monitoring Reader](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/monitor#monitoring-reader) |
| S10 | [Protect secrets in Azure PowerShell](https://learn.microsoft.com/powershell/azure/protect-secrets) |
| S11 | [Get-AzAccessToken](https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken) |
| S12 | [ConvertFrom-SecureString](https://learn.microsoft.com/powershell/module/microsoft.powershell.security/convertfrom-securestring#-asplaintext) |
| S13 | [Resolve responsible AI content filter errors](https://learn.microsoft.com/troubleshoot/power-platform/copilot-studio/generative-answers/agent-response-filtered-by-responsible-ai) |
| S14 | [Agent-level telemetry and settings](https://learn.microsoft.com/microsoft-copilot-studio/advanced-bot-framework-composer-capture-telemetry) |
| S15 | [AppEvents table](https://learn.microsoft.com/azure/azure-monitor/reference/tables/appevents) |
| S16 | [Azure Monitor ingestion time](https://learn.microsoft.com/azure/azure-monitor/logs/data-ingestion-time) |
| S17 | [Entra authorization for Blob PowerShell](https://learn.microsoft.com/azure/storage/blobs/authorize-data-operations-powershell) |
| S18 | [Immutable storage](https://learn.microsoft.com/azure/storage/blobs/immutable-storage-overview) |
| S19 | [Runbook execution and networking](https://learn.microsoft.com/azure/automation/automation-runbook-execution) |
| S20 | [Scheduled refresh](https://learn.microsoft.com/power-bi/connect-data/refresh-scheduled-refresh) |
| S21 | [Data/schema refresh](https://learn.microsoft.com/power-bi/connect-data/refresh-data) |
| S22 | [Azure Blob Storage connector authentication](https://learn.microsoft.com/power-query/connectors/azure-blob-storage) |
| S23 | [Incremental refresh](https://learn.microsoft.com/power-bi/connect-data/incremental-refresh-overview) |
| S24 | [Compress-Archive](https://learn.microsoft.com/powershell/module/microsoft.powershell.archive/compress-archive) |
| S25 | [Blob access tiers](https://learn.microsoft.com/azure/storage/blobs/access-tiers-overview) |
| S26 | [Exchange managed identity](https://learn.microsoft.com/powershell/exchange/connect-exo-powershell-managed-identity) |
| S27 | [Exchange app-only authentication](https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2) |
| S28 | [Conditional Access for workload identities](https://learn.microsoft.com/entra/identity/conditional-access/workload-identity) |
| S29 | [Create auditLogQuery v1.0](https://learn.microsoft.com/graph/api/security-auditcoreroot-post-auditlogqueries?view=graph-rest-1.0) |
| S30 | [New-MgSecurityAuditLogQuery](https://learn.microsoft.com/powershell/module/microsoft.graph.security/new-mgsecurityauditlogquery) |
| S31 | [New-MgBetaSecurityAuditLogQuery](https://learn.microsoft.com/powershell/module/microsoft.graph.beta.security/new-mgbetasecurityauditlogquery) |
| S32 | [Runbook output and messages](https://learn.microsoft.com/azure/automation/automation-runbook-output-and-messages) |
| S33 | [Application Insights SeverityLevel](https://learn.microsoft.com/dotnet/api/microsoft.applicationinsights.datacontracts.severitylevel) |

S6 was retrieved with `get_recent_azure_updates` (title search) followed by
`get_azure_update_by_id`, using the notice's slug as the ID. The full description
says, "We have extended the retirement date to September 30, 2026"; its modified
timestamp is 2026-04-21. This is a retirement-timing lookup, not a publication-date
filter or proof of actual service shutdown.

## Downstream artifacts reviewed

Discovery searched the solution identifier/title/links and repeated claims
including timing, exact telemetry predicates, severity, and Power BI settings.
Each unchanged disposition below concerns propagation of these corrections, not
a certification of every unrelated claim in that artifact.

| Artifact | Disposition and reason |
|---|---|
| `deny-event-correlation-report/docs/troubleshooting.md` | **Changed:** date, corrected diagnostics/claims, source links, and explicit unknowns. |
| `deny-event-correlation-report/docs/prerequisites.md` | **Changed:** telemetry discovery/checklist gate, test-canvas distinction, certificate caveat, authentication/retirement sources. |
| `deny-event-correlation-report/docs/architecture.md` | **Changed:** RAI assumptions, solution-specific per-agent scope, and incremental-refresh prerequisites. |
| `deny-event-correlation-report/README.md` | **Changed:** production RAI validation gate and verification-record link. |
| `deny-event-correlation-report/LAB-VALIDATION.md` | **Changed:** dated addendum supersedes the old unconditional RAI-readiness conclusion; historical validation and regulatory wording retained. |
| `deny-event-correlation-report/CHANGELOG.md` | **Changed:** Unreleased technical-verification entry; no release-version change. |
| `deny-event-correlation-report/scripts/Export-RaiTelemetry.ps1` | **Changed, comments only:** labels exact schema as an unverified solution assumption. Classifier, CSV shape, authentication, and runtime behavior retained rather than replaced speculatively. |
| `deny-event-correlation-report/kql-queries/content-filtered-events.kql` | **Changed, comments only:** same validation gate and primary source. |
| `deny-event-correlation-report/docs/verification-2026-10-16.md` | **Added:** durable PR-ready sources, discrepancies, downstream review, and validation record. |
| `deny-event-correlation-report/scripts/Export-CopilotDenyEvents.ps1` | **Unchanged:** already uses stable session paging, `ReturnLargeSet`, 5,000-row pages and warns at the configured result cap; no filter or permission behavior changed. |
| `deny-event-correlation-report/scripts/Export-DlpCopilotEvents.ps1` | **Unchanged:** already uses operation filtering and the same session paging; no corrected RAI/CA/refresh claim is embedded. |
| `deny-event-correlation-report/scripts/Export-DefenderCopilotEvents.ps1` | **Unchanged:** separate Graph hunting collector; no corrected RAI or refresh predicate dependency. |
| `deny-event-correlation-report/scripts/Connect-ExchangeOnlineHelper.ps1` | **Unchanged:** shown connection patterns remain valid; setup/runtime restrictions are clarified in the invoking guides, not a connection-logic change. |
| `deny-event-correlation-report/scripts/Invoke-DailyDenyReport.ps1` | **Unchanged:** orchestrates the existing collectors and Entra Blob upload. New documentation gates RAI use and distinguishes list access from write tests; no orchestration change required. |
| `deny-event-correlation-report/kql-queries/copilot-deny-events.kql` | **Unchanged:** independent audit-record query; no corrected timing, RAI, severity, or UI claim repeated. |
| `deny-event-correlation-report/kql-queries/dlp-copilot-matches.kql` | **Unchanged:** independent DLP operation query; no changed predicate shared with RAI diagnostics. |
| `deny-event-correlation-report/kql-queries/cloud-app-events.kql` | **Unchanged:** Defender query already separates tenant-shaped fields; no corrected RAI contract used. |
| `deny-event-correlation-report/kql-queries/correlation-analysis.kql` | **Unchanged:** consumes existing normalized output; the CSV interface was not changed. RAI-source readiness is now explicitly gated upstream. |
| `deny-event-correlation-report/.ralph-config.json` | **Unchanged:** records per-agent/table-shape context but not the disputed exact event/type/filter keys; no new Microsoft emission guarantee added. |
| `deny-event-correlation-report/manifest.yaml` | **Unchanged:** generic runbook/CSV verification remains necessary but must be read with the new positive-example RAI gate. No metadata or compliance mapping changed. |
| `deny-event-correlation-report/controls-covered.json` | **Regenerated, unchanged:** manifest/control coverage unchanged; mapping decisions are outside this review. |
| `compliance-dashboard/docs/prerequisites.md` | **Unchanged:** optional Deny Event source dependency only; no corrected diagnostic/schema claim restated. |
| `compliance-dashboard/docs/troubleshooting.md` | **Changed:** repeated old Power BI navigation and credential ownership. Other dashboard issues were not re-audited. |
| `compliance-dashboard/docs/power-bi-setup.md` | **Changed:** semantic-model refresh/settings terminology and source link. |
| `compliance-dashboard/docs/deployment-checklist.md` | **Changed:** same navigation, current schedule slider, and refresh-history evidence instead of an assumed success message. |
| `compliance-dashboard/CHANGELOG.md` | **Changed:** downstream correction entry. |
| `compliance-dashboard/README.md`, `.ralph-config.json` | **Unchanged:** dashboard scope/data model and naming facts are unaffected by the refresh-navigation correction. |
| `agent-observability-foundation/README.md`, `docs/pii-sanitization-guide.md` | **Unchanged:** related telemetry/configuration references do not prescribe the disputed exact RAI filter and already use Settings > Advanced. |
| `copilot-studio-analytics/README.md`, `docs/prerequisites.md` | **Unchanged:** independent analytics setup does not restate the corrected exact RAI classifier; Settings > Advanced is already documented. |
| `README.md`, `DEPLOYMENT-GUIDE.md`, `AGENTS.md`, `.github/copilot-instructions.md` | **Unchanged:** solution catalog/version/zone/control relationships unaffected. Catalog generator run; no manual catalog edits. |
| `CHANGELOG.md` | **Unchanged:** historical root release entries; new details live in solution Unreleased records. |
| `site-docs/getting-started/prerequisites.md` | **Unchanged:** generic Azure logging dependency, not a detailed RAI or refresh contract. |
| `.squad/skills/repo-context.md` | **Unchanged:** maintainer structure/validation context only. |
| `scripts/build-manifest.py`, `scripts/_backfill-zones.py` | **Unchanged:** identifier/navigation and historical zone mapping, not detailed product claims. |
| `mkdocs.yml` | **Unchanged:** existing navigation retained; the generated solution detail page automatically links the new verification record. |
| `solutions.json`, `site-docs/solutions/index.md`, `site-docs/reference/control-mapping.md`, `site-docs/index.md` | **Regenerated, unchanged:** manifest inventory, metrics, and compliance relationships unchanged with CI's framework v1.6.0 pin. |
| `site-docs/getting-started/deployment-guide.md`, `site-docs/reference/changelog.md` | **Regenerated, unchanged:** copies of unchanged root documents. |
| `site-docs/solutions/deny-event-correlation-report/index.md` | **Regenerated:** documentation links include this verification record; gitignored output. |
| `site-docs/solutions/deny-event-correlation-report/architecture.md`, `prerequisites.md`, `troubleshooting.md`, `verification-2026-10-16.md` | **Regenerated:** source mirrors, including the current Last Verified metadata; gitignored, not hand-edited. |
| `site-docs/solutions/compliance-dashboard/troubleshooting.md`, `power-bi-setup.md`, `deployment-checklist.md` | **Regenerated:** source mirrors of propagated navigation corrections; gitignored output. |

No `build_content_graph.py` or other content-graph generator exists in this
checkout. No external companion-repository content was modified. The linked
framework playbook is a separate repository and is not asserted to have been
updated by this local-only task.

## Generator and validation record

The generator initially discovered the sibling framework's unreleased 79-control
main state. To avoid altering any regulatory/control mapping, regeneration was
repeated with `FRAMEWORK_CONTROLS` pointing to a session-local copy of
`assessment/manifest/controls.json` read from the local framework **v1.6.0 tag**,
the pin used by this repository's documentation CI. No framework files were edited.

Commands:

```powershell
# Set FRAMEWORK_CONTROLS to the local v1.6.0 controls export before both invocations
python scripts\build-manifest.py
python scripts\build-manifest.py --check
python -m mkdocs build --strict
python -m pytest scripts\tests\ -q
python -m pytest -q --import-mode=importlib
python -m ruff check .
python scripts\validate-language-rules.py
python scripts\verify_commercial_scope.py
python scripts\sync-agent-md-versions.py --check
python scripts\lint-version-drift.py --strict
python scripts\lint-optionset-values.py --strict
python scripts\lint-odata-columns.py
python scripts\lint-odata-existence.py
```

Baseline results: 114 shared tests passed; full Python suite 1,321 passed,
2 skipped, with one existing pytest deprecation warning. Strict MkDocs, Ruff,
language/commercial-scope, version, option-set and OData-naming checks passed.
The OData-existence checker exited 0 but reported 17 existing findings outside
this solution; these are not claimed resolved. All six solution PowerShell files
parsed and solution-scoped PSScriptAnalyzer passed. No solution Pester test files
exist. Post-change pinned generation and `--check`, strict MkDocs,
language/commercial-scope checks, solution PowerShell parse and PSScriptAnalyzer,
and `git diff --check` also passed. Regeneration updated eight gitignored solution
pages (the Deny Event detail page plus four sub-docs, and three dashboard
sub-docs); tracked catalogs/mappings remained byte-identical. No live Microsoft
tenant was used.
