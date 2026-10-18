# Model Risk Management Automation - technical verification

**Last Verified:** 2026-10-16

This record addresses `judeper/OceanSquad#788`. Live Microsoft Learn search and fetch were used
to re-check the README's Microsoft product statements and their downstream
implementation, troubleshooting, checklist, and evidence instructions. This is
technical documentation verification, not a compliance assessment or a live-tenant
test. Regulatory wording, control membership, risk tiers, and institution policy
decisions were not reinterpreted or changed.

## Discrepancies and propagation

| Area | Finding and correction | Sources |
|---|---|---|
| Licensing | A blanket Microsoft 365 E3+ requirement conflated Teams/SharePoint services with Graph permissions. Specify service entitlements and API-specific authorization separately. Power Automate premium licensing depends on owner/invoker/Process context; approval responders alone do not require Premium. Add the missing Dataverse app-user licensing prerequisite. Approvals and SharePoint are standard connectors; Word Online (Business) is premium. | S1-S6, S10 |
| Agent 365 package API | Preview-only/delegated-only guidance is stale. List packages documents v1.0 and beta, application and delegated `CopilotPackages.Read.All`, and a Microsoft Agent 365 license. Delegated administrator role guidance remains AI Administrator or Global Administrator. Follow `@odata.nextLink` to completion. Corrected README, prerequisites, Flow 1, solution documentation, troubleshooting, checklist, and the historical lab-report supersession note. | S7-S9 |
| Entra provisioning and migration | Creation timing depends on harness: standard at creation, GitHub Copilot at first publish. Manual migration is preview, and preserves the application/client ID in place. Agent Builder agents do not currently require these identities. Separate the inventory Bot ID/environment alternate key from `fsi_entraagentid`; do not re-key model records on migration. | S11-S13 |
| Migration evidence | The README's `AgentIdMigration` string and invented columns were not a valid Dataverse create payload. Label the sample as an advisory JSON envelope in `fsi_eventdetails`, use the existing integer event Choice and required schema columns, and retain row/validation links. Replace schema-name-like sample Bot IDs with GUIDs and show preserved client IDs. `Test-MRMCompliance.ps1` does not check Entra identity validity or history continuity: add explicit before/after and channel/authentication checks to README and checklist. | S12-S14; local schema and report script |
| Administrator access | Power Platform service-admin assignment is not automatic Dataverse System Administrator/data access. Microsoft Graph application grants require an authorized privileged consent role, not Application Administrator. Corrected the manifest prerequisite so generated catalog detail and `solutions.json` agree with the existing README restriction. | S15-S17 |
| Managed identity grants | Enterprise applications does not supply the app-registration **Add a permission** workflow described in prerequisites. Follow the documented service-principal app-role assignment and read-back procedure. A Graph grant to a managed identity does not configure separate SharePoint/Word connector accounts. | S6, S16-S17 |
| Word template | The SharePoint guide prescribed unsupported Rich Text controls. Use uniquely titled Plain Text controls, discover every field through the bound connector, and test generation under intended access policies. Propagated to Flow 5, troubleshooting, solution documentation, and delivery checks. | S6 |
| LTR setup | The table/retention setup is in Power Apps, not an environment Settings toggle. Retention definitions are solution-aware, contrary to the previous assertion that solution portability is impossible. LTR archives inactive rows into read-only storage; it is not an automatic seven-year deletion rule or default live-row expiry. Corrected technical setup and added retrieval/criteria checks without changing the institution's specified retention duration or regulatory mappings. Deployment-script guidance points to these steps. | S18-S19 |
| Desktop self-healing | Existing preview status, build 2603, models, and single-element error examples remain supported. Added runtime-only scope, version/account/admin prerequisites, and unintended-element risk; replaced an unsupported blanket "not configurable" statement with the documented admin/per-action controls. Desktop flows remain outside this solution's implementation scope. | S20-S21 |

## Confirmed claims and limits

- Six custom tables, separate Bot ID/Entra identity columns, the two-column
  alternate key, event Choice integers, and required event columns match
  `scripts/create_mrm_dataverse_schema.py` and generated schema documentation.
- Dataverse `bot` metadata remains accessible through the documented Web API.
  Graph user reads support `User.Read.All` application access and explicit
  `$select` for nondefault properties such as department (S10, S14).
- Managed Environment remains required for LTR (S18). Canvas/model-driven apps,
  cloud-flow orchestration, SharePoint documents, and a Power BI report remain
  the solution's manually constructed architecture, not delivered runtime packages.
- Legacy beta Agent Registry identity cross-reference remains documented
  (`AgentInstance.Read.All`); registry convergence does not equate portal
  visibility rights with Package Management API licensing (S8-S9, S22).
- No README screenshots are present. No new Microsoft release or tenant rollout
  date was inferred from a roadmap. The identity overview and migration article
  disagree on whether automatic backfill is future or in progress; the README
  follows the migration-specific article, without asserting tenant completion.
  The release summary mentions July whereas the identity-specific rollout page
  says May; rollout timing is attributed to the identity page, not treated as a
  universal tenant guarantee.
- No tenant authentication, deployments, migrations, flow runs, connector tests,
  or retention jobs were performed. The checklist identifies these operator checks.
  Aggregate MRM reports are not substitutes for migration verification.

## Downstream artifacts reviewed

Within the first table, paths are relative to `model-risk-management-automation/`.
In grouped entries, abbreviated paths share the explicitly named solution or
template directory.

| Artifact | Status | Propagation or reason unchanged |
|---|---|---|
| `README.md` | Changed | Verification date, licensing/access, package API, self-healing scope, migration identities and evidence. |
| `docs/prerequisites.md` | Changed | Service licensing, grants/read-back, Dataverse role separation, optional API access. |
| `docs/flow-configuration.md` | Changed | Flow 1 package API and Flow 5 supported template/connection requirements. |
| `docs/sharepoint-setup.md` | Changed | Supported controls and connector-specific verification. |
| `docs/troubleshooting.md` | Changed | Maker portal navigation, Word generation, LTR and optional registry diagnostics. |
| `DELIVERY-CHECKLIST.md` | Changed | Licensing, connection, LTR, identity and evidence acceptance checks. |
| `SOLUTION-DOCUMENTATION.md` | Changed | Current API and linked technical setup limitations. |
| `LAB-VALIDATION.md` | Changed | Dated supersession note; original historical results retained, not rerun tenant evidence. |
| `CHANGELOG.md` | Changed | Unreleased technical-only correction record; no version bump for this documentation refresh. |
| `manifest.yaml` | Changed | Privileged consent-role prerequisite only; controls/version/description unchanged. |
| `scripts/deploy.py` | Changed | Printed post-deployment LTR navigation/semantics; no deployment logic change. |
| `scripts/Test-MRMCompliance.ps1` | Unchanged | Read to confirm it reports aggregate MRM status and does not verify identities or history; corrected its callers' claims rather than adding a new validator. |
| `scripts/Deploy-MRM-Baseline.ps1` | Unchanged | Baseline export does not migrate identities or generate Word documents. |
| `scripts/create_mrm_dataverse_schema.py`, `docs/dataverse-schema.md` | Unchanged | Canonical schema already separates IDs and supplies valid event Choices; documentation regenerated with no drift. |
| `scripts/create_mrm_environment_variables.py`, `scripts/create_mrm_connection_references.py`, `scripts/mrm_client.py`, `scripts/requirements.txt` | Unchanged | Configuration/deprecation/dependencies do not hardcode the corrected package route, migration procedure, or Word controls. |
| `templates/agent-card-content.sample.json` | Changed | Separate identity fields were correct, but their `bot-`/`agent-` prefixes were not valid GUIDs; removed the prefixes to match the re-verified identity format. |
| `templates/mrm-config.sample.json` | Unchanged | Feature flags remain compatible; no identity format or licensing claims. |
| `templates/adaptive-card-templates/validation-assignment.json`, `risk-scoring-notification.json`, `sla-breach-alert.json`, `revalidation-approval.json` | Unchanged | Workflow notifications contain none of the corrected licensing, identity-migration, template-control or LTR setup claims. |
| `.ralph-config.json`, `controls-covered.json` | Unchanged | Schema facts and generated control membership remain valid; no schema or control-mapping change. |
| `docs/verification-2026-10-16.md` | Added | Durable sources, discrepancies, review inventory and validation evidence for the parent PR. |
| `docs/power-apps-configuration.md` | Changed | Adds the app-user entitlement prerequisite so flow licensing is not mistaken for app licensing; app design unchanged. |
| `docs/powerbi-dashboard.md` | Unchanged | Report design does not restate corrected licensing/API/migration/template setup; no report behavior change. |

Additional identifier/title/link searches found these consumers:

| Artifact | Status | Reason |
|---|---|---|
| `agent-intake/README.md`, `docs/admin-onboarding-guide.md`, `docs/mrm-integration.md`, `docs/flow-configuration.md` | Unchanged | MRM handoff references and Bot ID/environment key already agree with the corrected inventory contract; no changes to separate intake identity provisioning or policy decisions. |
| `agent-intake/docs/dataverse-schema.md`, `scripts/create_fsi_intake_dataverse_schema.py`, `scripts/handoff_mrm.py`, `scripts/seed_classification_rules.py`, `templates/mrm-handoff-payload-schema.json`, `templates/policy-lookup-tables.yaml` | Unchanged | Handoff keeps platform and optional Entra IDs separate; schema/classification contracts do not depend on the corrected licensing, Word or retention setup. |
| `agent-intake/CHANGELOG.md`, `research/01-phase-a-fit-assessment.md`, `research/02-question-catalog-research-prompt.md` | Unchanged | Historical changelog/research references, not current MRM deployment instructions. |
| Root `README.md`, `DEPLOYMENT-GUIDE.md`, `AGENTS.md`, `.github/copilot-instructions.md`, `CHANGELOG.md` | Unchanged | Catalog/version/zone/dependency references remain accurate; no solution version or regulatory mapping change. |
| `environment-lifecycle-management/CHANGELOG.md`, `file-upload-security/CHANGELOG.md`, `agent-access-monitor/docs/verification-2026-10-16.md` | Unchanged | Historical or review cross-references, not restatements of corrected product claims. |
| `.squad/skills/repo-context.md`, `scripts/_backfill-zones.py` | Unchanged | Repo context and zone migration identifiers are unrelated to corrected product behavior. |
| `solutions.json` | Regenerated, changed | Manifest's corrected privileged consent-role prerequisite exported. |
| `site-docs/solutions/model-risk-management-automation/index.md` | Regenerated, changed | Detail prerequisite and new verification navigation emitted from manifest/source docs; gitignored. |
| `site-docs/solutions/model-risk-management-automation/prerequisites.md`, `flow-configuration.md`, `sharepoint-setup.md`, `troubleshooting.md`, `power-apps-configuration.md` | Regenerated, changed | Copies of corrected implementation/verification guidance; gitignored, not manually edited. |
| `site-docs/solutions/model-risk-management-automation/verification-2026-10-16.md` | Regenerated, added | Copies this dated verification record, including its Last Verified metadata; gitignored. The detail index is manifest-derived and does not copy the README metadata header. |
| `site-docs/solutions/model-risk-management-automation/dataverse-schema.md`, `powerbi-dashboard.md` | Regenerated, unchanged | Canonical schema and report design unchanged; gitignored. |
| `site-docs/solutions/index.md`, `site-docs/reference/control-mapping.md`, `site-docs/index.md`, root README table, all `controls-covered.json` exports | Regenerated, unchanged | Descriptions, controls, counts and versions unchanged using CI's pinned framework v1.6.0. |
| `mkdocs.yml` | Changed | Navigation exposes the new verification page. |
| `scripts/build-manifest.py` | Unchanged | Existing generator already copies the new source doc and projects manifest prerequisites; no content-graph generator exists in this repository. |

## Sources

All sources were queried live through Microsoft Learn on 2026-10-16.

| ID | Microsoft Learn URL |
|---|---|
| S1 | https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs |
| S2 | https://learn.microsoft.com/power-platform/admin/powerapps-flow-licensing-faq |
| S3 | https://learn.microsoft.com/office365/servicedescriptions/teams-service-description |
| S4 | https://learn.microsoft.com/connectors/approvals/ |
| S5 | https://learn.microsoft.com/connectors/sharepointonline/ |
| S6 | https://learn.microsoft.com/connectors/wordonlinebusiness/ |
| S7 | https://learn.microsoft.com/microsoft-365-copilot/extensibility/api/admin-settings/package/copilotpackages-list |
| S8 | https://learn.microsoft.com/microsoft-agent-365/admin/graph-api |
| S9 | https://learn.microsoft.com/entra/agent-id/agent-registry-convergence |
| S10 | https://learn.microsoft.com/graph/api/user-get?view=graph-rest-1.0 |
| S11 | https://learn.microsoft.com/microsoft-copilot-studio/admin-use-entra-agent-identities |
| S12 | https://learn.microsoft.com/microsoft-copilot-studio/govern-migrate-api-entra-agent-identity |
| S13 | https://learn.microsoft.com/microsoft-copilot-studio/govern-agents-identities-overview |
| S14 | https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/bot |
| S15 | https://learn.microsoft.com/power-platform/admin/use-service-admin-role-manage-tenant |
| S16 | https://learn.microsoft.com/entra/identity/enterprise-apps/grant-admin-consent |
| S17 | https://learn.microsoft.com/powershell/entra-powershell/grant-api-permissions-managed-identity |
| S18 | https://learn.microsoft.com/power-apps/maker/data-platform/data-retention-overview |
| S19 | https://learn.microsoft.com/power-apps/maker/data-platform/data-retention-set |
| S20 | https://learn.microsoft.com/power-automate/desktop-flows/self-healing |
| S21 | https://learn.microsoft.com/power-platform/released-versions/power-automate-desktop/2603 |
| S22 | https://learn.microsoft.com/graph/api/agentinstance-get?view=graph-rest-beta |

## Generator and validation evidence

Use `FRAMEWORK_CONTROLS` pointing to `assessment/manifest/controls.json` from
framework tag **v1.6.0**, matching `.github/workflows/docs-autonomy.yml`. The local
sibling checkout is newer (79 controls); its initial generated metric/mapping
drift was removed by rerunning the generator against the pinned 78-control input.
No framework mapping changes are included.

| Command | Result |
|---|---|
| `python model-risk-management-automation/scripts/create_mrm_dataverse_schema.py --output-docs` | Passed; `docs/dataverse-schema.md` regenerated without changes. |
| `python scripts/build-manifest.py` | Passed with pinned framework input; regenerated `solutions.json`, catalog/detail/index pages, control exports and normalized sub-doc copies. Only the consent prerequisite changes the tracked generated export. |
| `python scripts/build-manifest.py --check` | Passed with the same pinned input; no generated drift. |
| `python -m mkdocs build --strict --quiet` | Passed; rendered site regenerated, including the verification page. |
| `python -m pytest scripts/tests/ -q` | 120 passed. |
| `python -m pytest scripts/tests/test_docs_autonomy_protection.py -q` | 5 passed after navigation changes. |
| `python scripts/validate-language-rules.py` | Passed. |
| `python scripts/verify_commercial_scope.py` | Passed. |
| `python scripts/lint-odata-columns.py` | Passed, zero findings. |
| `python scripts/lint-odata-existence.py` | Report-only exit 0; 17 findings in unchanged files, including two cross-solution inventory columns in `scripts/Deploy-MRM-Baseline.ps1`. Not represented as a zero-finding run. |
| `python scripts/lint-odata-existence.py --solution model-risk-management-automation` | Report-only exit 0; the same two unchanged baseline-export findings. |
| `python scripts/sync-agent-md-versions.py --check` | Passed. |
| `python scripts/lint-version-drift.py --strict` | Passed. |
| `python scripts/lint-optionset-values.py --strict` | Passed, zero findings. |
| `python -m ruff check model-risk-management-automation/scripts/deploy.py` | Passed. |
| `python -m py_compile model-risk-management-automation/scripts/deploy.py` | Passed; only printed guidance changed. |
| `git diff --check` | Passed. |

Additional local assertions passed for unchanged README regulatory sections,
parseable JSON/CSV migration evidence, preserved sample application/client IDs,
GUID-shaped Agent Card identity examples, generated verification pages, and the
corrected manifest prerequisite in `solutions.json`.

No solution-specific Pester test files exist in this solution. No dependencies
were installed, remote state changed, or live CI run claimed by this worker.

## Owner-requested review - 2026-10-18 (UTC)

The review compared original head `6fa10a257a7195ea97d807f7a6f83bd6c99474c4`
with base `c13b640105e90020b68b5bdb66d36878c763639b` and the requirements in
`judeper/OceanSquad#788`. The isolated review branch then incorporated the already
reviewed `main` at `53b8db2e20e3e4e68e9ec97baa2470bc1570ea4f` before validation.

**Standards:** Checked the root `AGENTS.md`, Copilot instructions, language and
commercial-scope rules, and solution `.ralph-config.json`. Canonical schema,
generated-file ownership, supported content types, and technical-only scope were
preserved.

**Specification:** Confirmed the product corrections against live Microsoft Learn
search/fetch, including licensing, Agent 365 package permissions, identity
provisioning/migration, managed identity grants, Word controls, LTR, and
self-healing. The live identity article includes harness-specific provisioning;
an older cached web copy omitted that section. No rollout completion was inferred.

The README's later **MRM Alignment** summary still described `AgentIdMigration`
as a Dataverse event type, contradicting its corrected evidence instructions.
Corrected the summary to use **Material Change Detected**
(`fsi_eventtype = 100000010`) and keep the `AgentIdMigration` envelope inside
`fsi_eventdetails`. The schema generator and generated schema agree; no new
Choice or schema change is needed. Searches of the README, delivery checklist,
verification record, and intake handoff found no further contradictory migration
instructions. The original downstream inventory above remains applicable.

| Post-integration validation | Result |
|---|---|
| Schema `--output-docs`; pinned v1.6.0 catalog generation and `--check` | Passed; no tracked generated drift. |
| `python -m mkdocs build --strict --quiet` | Passed with the reviewed `main` changes integrated. |
| `python -m pytest scripts/tests/ -q` | 120 passed, including documentation-autonomy contracts. |
| Language, commercial scope, catalog agent versions, strict version drift, strict OptionSet lint | Passed; zero OptionSet findings. |
| Ruff and `py_compile` on `scripts/deploy.py` | Passed. |
| Deployment Python AST comparison against the original base | Executable code unchanged; only `POST_DEPLOYMENT_GUIDANCE` differs. |
| Local migration JSON/CSV, sample GUID, and schema/summary assertions | Passed; sample application/client IDs are preserved and the summary uses the deployed integer Choice. |
| Exact comparison of seven README regulatory/policy sections against the original base | Unchanged: Overview, Control Mapping, MRM Three-Pillar Coverage, MRM Scope Decision Matrix, Regulatory Alignment, Related Controls, and Migration Evidence Requirements. |
| `git diff --check` | Passed. |

The PR description must include the source and downstream tables above, together
with these review results. Local checks are not live-tenant validation or CI
evidence; no deployment, migration, permission change, or retention run was made.
