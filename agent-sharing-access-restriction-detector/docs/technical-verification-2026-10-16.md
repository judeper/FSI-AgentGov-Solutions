# Technical Verification Record - 2026-10-16

**Last Verified:** 2026-10-16
**Scope:** Microsoft product facts and local downstream documentation for ASARD v2.0.2.
No regulatory mappings or conclusions were changed. No tenant was accessed, and the
last lab-validation date remains **2026-06-09**. Microsoft Learn search and fetch were
used against live documentation; product documentation is not a runtime test.

## Findings and propagation

| Claim checked | Result and correction | Source |
|---|---|---|
| Managed Environment agent sharing limits | Confirmed Editor/Viewer settings, individual-only Editors, optional group restriction for Viewers, and viewer-count limits. | [Limit sharing](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-sharing-limits#agent-sharing-rules), [Control how agents are shared](https://learn.microsoft.com/en-us/microsoft-copilot-studio/admin-sharing-controls-limits) |
| Applicability and existing access | Confirmed authenticated-agent scope; existing shares are retained; the publish-to-bound-Team exception applies in Dataverse for Teams. No change to these README facts. | Same two sharing sources |
| Enforcement timing | Confirmed up to one hour for new sharing rules to start being enforced. Corrected flow-test instructions, lab interpretation, and gateway references that treated this as runtime chat-ACL PATCH propagation or a universal native-authorization delay. | [Limit sharing](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-sharing-limits#agent-sharing-rules) |
| Agent Store and navigation | Confirmed Agent Store discovery/installation and `Agents > All agents`, including **Available to** and **Deployed to**. Removed the unsupported April 2026 launch month. Separate admin surfaces are not evidence that deployment bypasses runtime ACLs; removed that inference in ASARD and UASD. | [Agent Store](https://learn.microsoft.com/en-us/microsoft-365/copilot/copilot-agent-store), [Agents admin guide](https://learn.microsoft.com/en-us/microsoft-365/copilot/agent-essentials/m365-agents-admin-guide) |
| Dataverse bot fields | Confirmed writable `accesscontrolpolicy` and `authorizedsecuritygroupids`, `bots` entity set, `botid`, policy `2` = Group membership, up to 20 comma-delimited Entra group IDs / 739 characters, and group-list semantics only under policy `2`. Current value `1` label is **Agent readers**, formerly **Copilot readers**; code uses numeric values, so no code change. Metadata persistence is not proof of channel enforcement. | [Bot reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot) |
| Dataverse paging | Corrected `$skip` from a supposed large-query limitation to an unsupported query option. Follow the opaque server-issued `@odata.nextLink` unchanged, or configure connector pagination. The 5,000-row figure is a standard-table page limit, not total query coverage; a view alone does not solve completeness. No flow export exists in this repository; multi-page Flow B execution remains untested. | [Page results](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/query/page-results), [List rows pagination](https://learn.microsoft.com/en-us/power-automate/dataverse/list-rows#turn-on-pagination) |
| Approval wait and total duration | Confirmed the 28-day approval wait caveat and separate 30-day total run duration. Corrected the cumulative-loop inference: four seven-day waits = 28 days plus overhead; five = 35 days. Sequential execution or a synchronously awaited child alone does not solve total-run budgeting. Seven days and a below-28-day cumulative safety margin are ASARD conventions, not Microsoft defaults/limits. | [Approvals known issues](https://learn.microsoft.com/en-us/power-automate/approvals-known-issues), [Duration limits](https://learn.microsoft.com/en-us/power-automate/limits-and-config#duration-limits), [Long-running approvals](https://learn.microsoft.com/en-us/power-automate/modern-approvals#create-long-running-approvals) |
| Split approval actions | Microsoft recommends calling Create/Wait close together to reduce an early-response race; strict designer adjacency is an ASARD build convention, not a platform requirement. Corrected attribution and linked explicit budget/deferral tests. | [Approvals known issues](https://learn.microsoft.com/en-us/power-automate/approvals-known-issues#split-create-and-wait-actions) |
| Licensing | Approvals is standard. Corrected the Premium rationale to ASARD's Dataverse/HTTP connector use and pointed to Premium/Process licensing choices; this does not make all ASARD workflows standard-connector flows. | [Approvals prerequisites](https://learn.microsoft.com/en-us/power-automate/get-started-approvals#prerequisites), [Dataverse connector](https://learn.microsoft.com/en-us/connectors/commondataserviceforapps/), [Licensing FAQ](https://learn.microsoft.com/en-us/power-platform/admin/power-automate-licensing/faqs) |
| Administrative identity and permissions | Confirmed management-app registration plus `Add-PowerAppsAccount` / `Get-AdminPowerAppEnvironment`, and separate per-environment Dataverse application-user roles. Graph permissions are separate from Dataverse access. Documented the shipped scan/exporter authentication limitations rather than implying managed-identity/certificate switches exist. No credential or authentication-state inspection was performed. | [Management applications](https://learn.microsoft.com/en-us/power-platform/admin/powershell-create-service-principal), [Application users](https://learn.microsoft.com/en-us/power-platform/admin/manage-application-users), [Get group permissions](https://learn.microsoft.com/en-us/graph/api/group-get?view=graph-rest-1.0) |
| Custom zone verification | Custom integers remain environment-specific. Corrected the prerequisites' ambiguous 1/2/3 storage description to `100000000`-series choices. Replaced `$expand=Options` with retrieval of the named global option-set definition; `Options` is not a navigation property. | [Query metadata / global option sets](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/query-metadata-web-api#query-global-option-sets) |
| Local implementation and evidence | Reviewed schema, policy engines, scan/export/integrity scripts, and adaptive-card usage against the README. Corrected the claim that mutable `fsi_remediation*` columns are inherently immutable history. Python dependency list remains `azure-identity`, `msal`, `requests`; the Python minimum is a code prerequisite, not a new Microsoft feature claim. SHA-256 evidence and the June detection/write results are retained as historical observations, not newly reproduced results. No screenshots are present in the README. | Local source files and `LAB-VALIDATION.md` |

## Sources

Live Microsoft Learn sources used for the claim checks above:

- [Managed Environment sharing limits](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-sharing-limits#agent-sharing-rules)
- [Copilot Studio sharing controls and authentication scope](https://learn.microsoft.com/en-us/microsoft-copilot-studio/admin-sharing-controls-limits)
- [Microsoft 365 Copilot Agent Store](https://learn.microsoft.com/en-us/microsoft-365/copilot/copilot-agent-store)
- [Microsoft 365 agents admin guide](https://learn.microsoft.com/en-us/microsoft-365/copilot/agent-essentials/m365-agents-admin-guide)
- [Dataverse bot table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot)
- [Dataverse Web API paging](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/query/page-results)
- [Dataverse List rows pagination](https://learn.microsoft.com/en-us/power-automate/dataverse/list-rows#turn-on-pagination)
- [Approvals known issues](https://learn.microsoft.com/en-us/power-automate/approvals-known-issues)
- [Cloud-flow duration limits](https://learn.microsoft.com/en-us/power-automate/limits-and-config#duration-limits)
- [Long-running approvals](https://learn.microsoft.com/en-us/power-automate/modern-approvals#create-long-running-approvals)
- [Approvals licensing prerequisites](https://learn.microsoft.com/en-us/power-automate/get-started-approvals#prerequisites)
- [Microsoft Dataverse connector](https://learn.microsoft.com/en-us/connectors/commondataserviceforapps/)
- [Power Automate licensing FAQ](https://learn.microsoft.com/en-us/power-platform/admin/power-automate-licensing/faqs)
- [Power Platform management applications and cmdlets](https://learn.microsoft.com/en-us/power-platform/admin/powershell-create-service-principal)
- [Dataverse application users and roles](https://learn.microsoft.com/en-us/power-platform/admin/manage-application-users)
- [Microsoft Graph get-group permissions](https://learn.microsoft.com/en-us/graph/api/group-get?view=graph-rest-1.0)
- [Dataverse global option-set metadata retrieval](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/webapi/query-metadata-web-api#query-global-option-sets)

## Downstream artifacts reviewed

Paths below are relative to the repository root. Grouped rows explicitly name files
with the same review outcome; "unchanged" means no propagation of these factual
corrections was required, not that every unrelated claim in that file was re-audited.

| Artifact | Outcome and reason |
|---|---|
| `agent-sharing-access-restriction-detector/README.md` | Changed: verification date, factual corrections, source links, and companion-guide warning. Lab date and control mappings retained. |
| `agent-sharing-access-restriction-detector/docs/flow-configuration.md` | Changed: paging mechanism, approval budgets, field semantics, runtime-test criteria, and legacy-guide warning. |
| `agent-sharing-access-restriction-detector/docs/approvals-limits.md` | Changed: distinct approval/run limits, local adjacency convention, persisted overflow, and boundary-test acceptance criteria. |
| `agent-sharing-access-restriction-detector/docs/prerequisites.md` | Changed: licensing rationale, stored zone integers, identity implementation boundaries, and per-environment privileges. |
| `agent-sharing-access-restriction-detector/docs/option-set-integers.md` | Changed: supported metadata retrieval used by verification operators; no custom option values changed. |
| `agent-sharing-access-restriction-detector/LAB-VALIDATION.md` | Changed: dated source clarification, accurate approval source/budget, and removal of the unsupported runtime propagation bound. Recorded execution results and hashes unchanged. |
| `agent-sharing-access-restriction-detector/CHANGELOG.md` | Changed: new Unreleased documentation entry; prior verification history retained. |
| `agent-sharing-access-restriction-detector/docs/technical-verification-2026-10-16.md` | Added: this durable findings/source/downstream record. |
| `agent-sharing-access-restriction-detector/docs/dataverse-schema.md` | Regenerated; unchanged: no schema/option-set change, and the current metadata already matches the script. |
| `agent-sharing-access-restriction-detector/controls-covered.json` | Regenerated; unchanged: partial-coverage gaps and staged-remediation caveat already recorded. No control interpretation changed. |
| `agent-sharing-access-restriction-detector/manifest.yaml` | Unchanged: catalog-level description/prerequisites do not state `$skip`, approval duration, Agent Store bypass, or PATCH propagation timing. No version/schema change. |
| `agent-sharing-access-restriction-detector/.ralph-config.json` | Unchanged: solution-specific zone, escaping, and schema facts unaffected. |
| `agent-sharing-access-restriction-detector/scripts/asard_zone_rules.py`, `scripts/asard_group_admission.py` | Unchanged: zone/group-admission policies do not depend on corrected product claims. Group admission reads local input; Graph lookup is reserved. |
| `agent-sharing-access-restriction-detector/scripts/create_asard_dataverse_schema.py`, `scripts/create_asard_environment_variables.py`, `scripts/create_asard_connection_references.py`, `scripts/requirements.txt` | Unchanged: schema, configured seven-day timeout, connector IDs, and dependency declarations remain valid for these corrections. Schema generator run offline only. |
| `agent-sharing-access-restriction-detector/scripts/governance/Invoke-SharingComplianceScan.ps1`, `Export-SharingComplianceEvidence.ps1` | Unchanged: both already follow server-issued `@odata.nextLink`; neither implements the README's alleged `$skip` remediation. Authentication limitations are documented, not repaired in this documentation lane. |
| `agent-sharing-access-restriction-detector/scripts/governance/Test-AgentSharingCompliance.ps1`, `Get-ExpectedSharingPolicy.ps1`, `Test-EvidenceIntegrity.ps1` | Unchanged: orchestration, zone policies, and hash verification do not implement cloud-flow approval/paging or claim PATCH runtime proof. |
| `agent-sharing-access-restriction-detector/templates/adaptive-card-asard-alert.json`, `adaptive-card-asard-remediation-approval.json`, `adaptive-card-asard-remediation-result.json`, `adaptive-card-asard-exception-expiring.json`, `adaptive-card-asard-exception-expired.json` | Unchanged: payload templates do not define paging, connector licensing, or access enforcement. Remediation cards remain external-integration reference templates, not the staged flow's runtime implementation. |
| `DEPLOYMENT-GUIDE.md` | Changed: ASARD row now distinguishes detection/metadata-write evidence from unvalidated end-to-end Flow B execution. |
| `agent-eligibility-gateway/README.md`, `agent-eligibility-gateway/docs/architecture.md` | Changed: propagated sharing-rule timing scope; removed the inference that native authorization is absent. Owned-channel gateway scope unchanged. |
| `unrestricted-agent-sharing-detector/README.md` | Changed: removed repeated Agent Store independence/bypass inference; retained the documented separate-inventory scope. |
| `credential-oversharing-detector/README.md` | Unchanged: links to recipient governance, without asserting corrected timing/paging/approval claims. |
| `copilot-agent-inventory/docs/governance-platform-composition.md` | Unchanged: ASARD detective-reuse reference and zone-policy row remain accurate; no enforcement timing or full-coverage claim. |
| `agent-eligibility-gateway/docs/architecture.md` detective-reuse diagram | Reviewed with changed architecture file; the ASARD reference itself is unchanged. |
| `copilot-billing-governance/README.md`, `docs/architecture.md`, `docs/dataverse-schema.md`, `scripts/create_cbg_dataverse_schema.py`, `manifest.yaml`, `CHANGELOG.md` | Unchanged: reuse of the local ASARD group-admission shape, not Agent Store/runtime/paging claims. Generated schema needs no change. |
| `environment-lifecycle-management/README.md`, `docs/dataverse-schema.md` | Unchanged: shared zone-classification references, unaffected by product corrections; no zone-policy changes. |
| `agent-access-monitor/LAB-VALIDATION.md`, `scripts/create_dataverse_schema.py` | Unchanged: analogous metadata-versus-runtime evidence boundary and schema-helper reuse remain accurate. |
| `cross-tenant-external-sharing-governance/scripts/governance/Scan-ManagedEnvBotSharingBaseline.ps1`, `scripts/create_ctsg_dataverse_schema.py`, `CHANGELOG.md` | Unchanged: native-baseline complement and schema-helper reuse, not the corrected chat-ACL propagation assumption. |
| `credential-oversharing-detector/scripts/create_cod_dataverse_schema.py`, `scripts/create_cod_environment_variables.py`, `CHANGELOG.md`; `file-upload-security/scripts/fus_client.py` | Unchanged: references to shared schema/client implementation patterns, not changed feature behavior. |
| `scripts/_backfill-zones.py`, `scripts/tests/test_build_manifest_partial_controls.py`, `scripts/tests/test_lint_optionset_values.py` | Unchanged: zone defaults and partial-control/choice contracts do not depend on the corrected product statements. |
| `README.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `.squad/skills/repo-context.md`, root `CHANGELOG.md` | Unchanged: catalog/history/context references; no corrected technical details repeated and no solution version bump. |
| `solutions.json`, `site-docs/solutions/index.md`, `site-docs/reference/control-mapping.md`, `site-docs/index.md` | Regenerated; unchanged with the CI-pinned framework v1.6.0: mappings, counts, and manifest metadata did not change. No verification date is stored in these catalog outputs. |
| `site-docs/getting-started/deployment-guide.md` | Regenerated; changed to mirror the ASARD scope correction in the source deployment guide. |
| `site-docs/solutions/agent-sharing-access-restriction-detector/index.md` and copied `approvals-limits.md`, `dataverse-schema.md`, `flow-configuration.md`, `option-set-integers.md`, `prerequisites.md`, `technical-verification-2026-10-16.md` | Regenerated, gitignored site outputs: corrected sub-docs and new verification record copied from sources, index updated to link sub-docs. No manual edits to generated files. The detail overview is manifest-derived, not a README copy. |
| `site-docs/solutions/agent-eligibility-gateway/architecture.md`, `site-docs/reference/changelog.md`, other solution detail pages/sub-docs | Regenerated, gitignored: gateway architecture correction propagated; remaining outputs unchanged in content. Solution READMEs are not copied verbatim by this generator. |
| `scripts/build-manifest.py`, `scripts/manifest.schema.json`, `scripts/controls-covered.schema.json`, `mkdocs.yml` | Unchanged: existing generator and navigation discover/link the new sub-doc. No content-graph generator exists in this repository. |

## Companion playbooks outside this worktree

These three linked public pages were fetched and reviewed, including deployment
verification, exception validation, troubleshooting, and evidence instructions.
They belong to **judeper/FSI-AgentGov**, not this worktree. They remain **unchanged
and require a separate authorized companion-repository correction**; this record
does not claim cross-repository completion. Local README/flow-guide warnings now
explicitly stop operators from using incompatible commands and schema examples.

| Reviewed page | Discrepancy / local replacement |
|---|---|
| [ASARD deployment guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/) | Describes `gov_asard*` tables, `detect_agent_sharing_violations.py` / `remediate_agent_sharing.py`, and importing nonexistent `src/` workflow exports. Use the shipped PowerShell scan, generated `fsi_*` schema, and manual flow guide here. Its verification examples do not validate this implementation. |
| [Exception management](https://judeper.github.io/FSI-AgentGov/playbooks/asard-exception-management/) | Uses a separate `gov_asardexception` table, legacy status values, legacy zone labels, and Python verification commands. This implementation uses `fsi_exception*` columns on `fsi_agentsharingcompliance`, status `100000002` for Exception / `100000001` for NonCompliant, and the canonical zone choices in the local metadata verification guide. Preserve justification/audit fields when expiring exceptions as specified in the local flow guide; do not copy the legacy clear-all-fields instruction. |
| [Troubleshooting](https://judeper.github.io/FSI-AgentGov/playbooks/asard-troubleshooting-guide/) | Uses legacy Python scripts/`gov_asard*` queries and recommends direct `principalobjectaccess` PATCH for sharing. ASARD's chat-ACL remediation is the combined `bots` column write plus independent read-back; authoring sharing uses supported sharing messages and remains out of scope. Do not treat these legacy diagnostics as an ASARD v2.0.2 verification checklist. |

The README's existing control links were reviewed as references, not re-interpreted.
External regulatory/control text was not changed or assessed for sufficiency.

## Regeneration and validation

Use the same framework controls input as CI: the published **v1.6.0**
`assessment/manifest/controls.json`, set through `FRAMEWORK_CONTROLS`.
The adjacent development checkout currently contains 79 controls rather than the
pinned 78 and would introduce unrelated catalog/count drift; it was not used to
regenerate committed outputs.

Commands run from the repository root (PowerShell paths):

```powershell
python agent-sharing-access-restriction-detector\scripts\create_asard_dataverse_schema.py --output-docs
python scripts\build-manifest.py
python scripts\build-manifest.py --check
python scripts\validate-language-rules.py
python scripts\verify_commercial_scope.py
python scripts\sync-agent-md-versions.py --check
python scripts\lint-version-drift.py --strict
python scripts\lint-optionset-values.py --strict
python -m pytest scripts\tests -q
python -m mkdocs build --strict
```

The manifest generator also regenerates all per-solution `controls-covered.json`
exports, README/catalog/hero blocks, control mapping, solution detail pages and
sub-doc copies, plus root deployment/changelog mirrors. No separate graph generator
was found. No Microsoft tenant runtime, approval execution, or live credential
validation was performed; those historical/operational boundaries remain explicit.

**Results:** manifest drift check and strict MkDocs build passed with the pinned
framework input. Language, commercial-scope, catalog-version, strict version-drift,
and strict option-set checks passed. The repository validator/generator contract
suite passed: **114 tests**. These local results do not claim execution of
GitHub-hosted security jobs or tenant runtime tests.
