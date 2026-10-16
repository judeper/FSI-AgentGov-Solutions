# Technical verification record - 2026-10-16

## Scope and method

Re-checked the Microsoft product claims in `agent-access-monitor/README.md` using
live Microsoft Learn `microsoft_docs_search` and `microsoft_docs_fetch` results.
This is a documentation-accuracy review, not a new tenant validation or a
regulatory assessment. Regulatory wording, control relationships, coverage
decisions, release versions, scripts, and manifests were not changed.

The separate primary-source research pass used the research-capable agent type.
Repository tracing checked the shipped scripts and templates as implementation
evidence, not as authority for Microsoft product behavior. The key adversarial
findings were the per-agent/per-maker distinction, the unsupported runtime
combination, the Premium Dataverse connector in the deferred-hosting model, and
the distinction between an environment-policy scan and per-agent access evidence.

## Claims checked and discrepancies

| Claim or surface | Finding and disposition |
|---|---|
| Setting names and values | S1 documents `bot-limitSharingMode` with `ExcludeSharingToSecurityGroups` / `noLimit`, `bot-authoringSharingDisabled` with `True` / `False`, and the `bot-maxLimitUserSharing` example `20`. Names and README zone-table values retained. Zone requirements are repository policy, not Microsoft defaults. |
| Viewer-cap scope | **Corrected:** the cap is the number of viewers for **each agent**, not an aggregate per-maker cap. S1/S2 make the viewer cap conditional on individual-only sharing (no security groups). |
| `Capped` / `Uncapped` | **Clarified:** these are AAM comparison categories. S1 does not define `0` or `-1` for the bot-prefixed viewer cap; its `-1` removal example is for the separate canvas-app field. Non-positive, missing, or non-integer input is treated conservatively by AAM, not certified as a Microsoft "unlimited" value. Raw captured values must be retained. |
| Authentication scope | Confirmed in S2: sharing limits apply only to agents requiring authentication. AAM scans environment configuration; it does not establish authentication or actual audience for every agent. |
| Enforcement and old access | **Clarified:** S1/S2 say changes can take up to an hour to start enforcement, not a fixed one-hour request delay. Existing access is not revoked; an agent over the new limit can only be unshared until it meets the rules. Propagated this wording to the gateway/composition guidance. |
| Portal navigation | S1 documents **Manage > Environments > select Managed Environment > Edit Managed Environments > Manage sharing**. Added a verification checklist using that path. No screenshots were present in the source README. |
| PowerShell install/sign-in/query | S3/S4 confirm the administration module, `Install-Module`, and `Add-PowerAppsAccount`; S1/S5 show `Get-AdminPowerAppEnvironment`, the `Internal.properties.governanceConfiguration.settings.extendedSettings` read path, and `Set-AdminPowerAppEnvironmentGovernanceConfiguration`. The collector uses the environment object, not an assumed standalone governance getter. |
| Runtime compatibility | **Corrected support implication:** S3 requires Windows PowerShell 5.x and describes .NET Framework dependencies as incompatible with PowerShell 6.0 and later. AAM's comparison script requires 7.0+, and its runbook/module/export require 7.4+. Documented this unresolved integration boundary rather than advertising 7.4 as supported by Microsoft or prescribing an unimplemented bridge. |
| Managed Environment licensing | S6 lists qualifying plans/meters and their conditions. Added the licensing prerequisite without treating admin roles as licenses or claiming that all Microsoft 365 plans qualify. |
| Daily-flow licensing | **Corrected:** S7 classifies Microsoft Dataverse as Premium for Power Automate. Deferring Azure Automation does not remove that requirement. S8 distinguishes owner licensing for scheduled flows from Process licensing allocated to a flow; no blanket claim that every alert recipient needs Premium was added. |
| Graph package APIs | **Qualified:** S9 documents `GET /beta/copilot/admin/catalog/packages`, the beta production-use restriction, and the Microsoft Agent 365 license requirement. This is not a dependency or collector in current AAM. |
| Legacy Agent Registry | **Corrected lifecycle shorthand:** S10 announces replacement of the legacy Graph Agent Registry APIs by Agent 365-based APIs starting May 2026. Removed the undifferentiated "both preview candidates" recommendation. This review does not claim that any particular replacement endpoint is generally available. |
| Export and evidence interface | Local script inspection confirms PowerShell 7.4+ and `-ClientId` for the device-code helper, with certificate-thumbprint authentication rejected. Fixed README/export examples and the stale parameter table. The basic scan example does not persist history unless `-PersistResults` and connection parameters are supplied. |
| Intake integration | **Corrected scope implication:** shipped AAM reads environment settings and zone baselines, not service-principal grants or intake decision packs. Marked the downstream per-agent permission rules as a proposed adapter contract, not shipped functionality. |
| Output, filtering, severity, persistence, hashing | Reviewed the orchestrator, comparison, export, integrity checker, helpers, and templates. These are repository features, not Microsoft platform promises; no behavior or severity-policy change was made. |

## Sources

All URLs below were checked through the live Microsoft Learn tools. They support
product facts only; they are not evidence of tenant configuration or regulatory
outcomes.

| ID | Microsoft Learn source |
|---|---|
| S1 | [Limit sharing in Managed Environments](https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits) |
| S2 | [Configure sharing controls and limits for agents](https://learn.microsoft.com/microsoft-copilot-studio/admin-sharing-controls-limits) |
| S3 | [Power Apps PowerShell support and installation](https://learn.microsoft.com/power-platform/admin/powerapps-powershell) |
| S4 | [Get started with the Power Apps administration module](https://learn.microsoft.com/powershell/powerapps/get-started-powerapps-admin) |
| S5 | [Set-AdminPowerAppEnvironmentGovernanceConfiguration](https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/set-adminpowerappenvironmentgovernanceconfiguration) |
| S6 | [Managed Environment licensing](https://learn.microsoft.com/power-platform/admin/managed-environment-licensing) |
| S7 | [Microsoft Dataverse connector reference](https://learn.microsoft.com/connectors/commondataserviceforapps/) |
| S8 | [Power Automate licensing FAQ](https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs) |
| S9 | [List Copilot packages](https://learn.microsoft.com/microsoft-365-copilot/extensibility/api/admin-settings/package/copilotpackages-list) |
| S10 | [Legacy Graph agentRegistry resource](https://learn.microsoft.com/graph/api/resources/agentregistry?view=graph-rest-beta) |
| S11 | [Dataverse security roles and privileges](https://learn.microsoft.com/power-platform/admin/security-roles-privileges) |

S11 confirms cumulative privileges and the distinction between Create, Read,
Write, and Delete, supporting retention of the existing role-design caveat.

## Downstream artifacts reviewed

Discovery searched the solution identifier, title, Control 3.8 links, all three
`bot-*` keys, the per-maker claim, API lifecycle wording, and the repeated latency
claim. "Unchanged" means no propagation of these specific corrections was needed;
it does not imply a fresh review of every unrelated claim in that artifact.

| Artifact | Disposition and reason |
|---|---|
| `agent-access-monitor/README.md` | **Changed:** verification date, corrected claims, runtime gate, export client ID, and verification checklist. |
| `agent-access-monitor/CHANGELOG.md` | **Changed:** Unreleased documentation entry; historical release entries retained. |
| `agent-access-monitor/LAB-VALIDATION.md` | **Changed:** dated documentation-only correction, per-agent cap, and Premium connector caveat; historical tenant observations and coverage limitations retained. |
| `agent-access-monitor/docs/prerequisites.md` | **Changed:** runtime incompatibility gate and Managed Environment / scheduled-flow licensing. |
| `agent-access-monitor/docs/flow-configuration.md` | **Changed:** local-host and Automation compatibility gates, Dataverse Premium requirement, testing prerequisite, and fourth optional connection reference. |
| `agent-access-monitor/docs/troubleshooting.md` | **Changed:** connector licensing, runtime incompatibility, sharing-rule scope/propagation, local cap categories, and export runtime requirement. |
| `agent-access-monitor/docs/evidence-export.md` | **Changed:** 7.4 minimum, required client ID in interactive examples, and current authentication parameter table. Regulatory descriptions retained. |
| `agent-access-monitor/docs/dataverse-schema.md` | **Changed:** raw per-agent cap versus AAM categories; optional Automation path and Premium connector. No schema or column-name change. |
| `agent-access-monitor/docs/role-design-append-only.md` | **Unchanged:** already distinguishes role-designed append-only behavior from platform immutability and notes cumulative role privileges; no viewer-cap or licensing claim. |
| `agent-access-monitor/docs/verification-2026-10-16.md` | **Added:** this durable source/discrepancy/downstream record for the trusted parent's PR summary. |
| `agent-access-monitor/manifest.yaml` | **Unchanged:** description and verification remain environment-level; no per-maker, API lifecycle, or no-Premium claim. No metadata or mapping revision required. |
| `agent-access-monitor/controls-covered.json` | **Unchanged:** already distinguishes configuration-only coverage, retained shares, propagation delay, and lab limitations. Coverage decisions were out of scope. |
| `agent-access-monitor/templates/zone-settings-baseline.json` | **Unchanged:** already describes per-agent viewers and local normalization. The configured zone policy and category behavior were not changed. |
| `agent-access-monitor/templates/adaptive-card-access-alert.json` | **Unchanged:** generic validation alert, no per-maker/licensing/lifecycle claim. |
| `agent-access-monitor/templates/adaptive-card-zone-access-alert.json` | **Unchanged:** displays validation context; no corrected product claim embedded. |
| `agent-intake/README.md` | **Changed:** narrows the AAM relationship to environment configuration rather than implying shipped per-agent grant validation. |
| `agent-intake/docs/drift-detection-integration.md` | **Changed:** explicitly labels per-agent permission comparison as a proposed adapter and prevents use of AAM results as per-agent approval evidence. |
| `agent-intake/docs/admin-onboarding-guide.md` | **Unchanged:** identifies handoff consumers without asserting the cap, licensing, runtime, or AAM grant-enumeration behavior. |
| `agent-intake/research/02-question-catalog-evaluation.md` | **Unchanged:** historical research explicitly flags an unverified security-advisory question; not current AAM implementation guidance. |
| `agent-intake/research/03-intake-form-design-v1.md` | **Unchanged:** historical design proposals; current executable integration boundary is clarified in the linked maintained guide. |
| `agent-intake/CHANGELOG.md` | **Unchanged:** historical integration entry, not a current product contract. |
| `agent-eligibility-gateway/README.md` | **Changed:** replaces fixed/roughly-hour latency with change-propagation semantics and authenticated-agent / retained-access boundaries. |
| `agent-eligibility-gateway/docs/architecture.md` | **Changed:** same correction in the native-path diagram, prose, and control-layer table. Gateway logic and regulatory mappings untouched. |
| `copilot-agent-inventory/docs/governance-platform-composition.md` | **Changed:** propagates latency/scope limits and legacy Registry replacement notice; retains AAM's environment-level role. |
| `copilot-agent-inventory/docs/dataverse-schema.md` | **Unchanged:** already distinguishes per-agent sharing posture from environment-wide sharing policy. |
| `copilot-agent-inventory/CHANGELOG.md` | **Unchanged:** historical environment/per-agent distinction remains accurate. |
| `unrestricted-agent-sharing-detector/docs/flow-configuration.md` | **Unchanged:** already distinguishes authenticated-agent scope and prospective rules from retroactive access removal. |
| `unrestricted-agent-sharing-detector/README.md` | **Unchanged:** refers to package API preview and separates package assignments from environment controls; no per-maker cap or fixed-latency assertion. |
| `cross-solution-integration/README.md` | **Unchanged:** AAM dashboard-feed reference only. |
| `cross-solution-integration/PREREQUISITES.md` | **Unchanged:** AAM feed/minimum-version dependency, not a corrected sharing or licensing claim. |
| `cross-solution-integration/docs/schema-contract.md` | **Unchanged:** schema/entity-set and evidence exchange contract; none of the corrected product claims alters it. |
| `cross-solution-integration/LAB-VALIDATION.md` | **Unchanged:** historical schema validation; no corrected product behavior restated. |
| `cross-solution-integration/CHANGELOG.md` | **Unchanged:** historical schema findings remain unrelated. |
| `cross-tenant-external-sharing-governance/LAB-VALIDATION.md` | **Unchanged:** historical setting observations and its own local threshold policy; no per-maker cap claim. |
| `content-moderation-monitor/README.md` | **Unchanged:** shared Control 3.8 link and separate package API discussion already distinguish product inventory from configuration data. |
| `hitl-workflow-governance/README.md` | **Unchanged:** shared Control 3.8 dashboard link only, not AAM sharing semantics. |
| `inactivity-timeout-enforcement/README.md` | **Unchanged:** shared Control 3.8 relationship, separate timeout implementation. |
| `agent-365-lifecycle-governance/README.md` | **Unchanged:** its independent API integration already notes beta/preview and May 2026 convergence; not an AAM collector or per-maker claim. |
| `agent-365-lifecycle-governance/docs/flow-configuration.md` | **Unchanged:** already includes the legacy API convergence caveat; its separate runtime implementation was not altered. |
| `agent-365-lifecycle-governance/DELIVERY-CHECKLIST.md` | **Unchanged:** already requires API validation and notes the May 2026 convergence. |
| `model-risk-management-automation/CHANGELOG.md` | **Unchanged:** historical entry already notes legacy Registry convergence. |
| `README.md` | **Regenerated, unchanged:** manifest-driven solution description/version table has none of the corrected detailed claims. |
| `DEPLOYMENT-GUIDE.md` | **Regenerated, unchanged:** environment-monitor role, layer/version table, and zone availability unaffected. |
| `AGENTS.md` | **Unchanged:** catalog entry only; no version or control change. |
| `.github/copilot-instructions.md` | **Unchanged:** catalog entry only. |
| `.squad/skills/repo-context.md` | **Unchanged:** maintainer structure/validation context, not product guidance. |
| `scripts/README.md` | **Unchanged:** benchmark scenario maps to AAM/3.8, not a new sharing or runtime contract. |
| `mkdocs.yml` | **Unchanged:** existing solution subpage navigation retained; the generated AAM detail page automatically links this additional verification document. |
| `solutions.json` | **Regenerated, unchanged:** no manifest/schema metadata changed; this index does not project README Last Verified. |
| `site-docs/solutions/index.md` | **Regenerated, unchanged:** catalog metadata unaffected. |
| `site-docs/reference/control-mapping.md` | **Regenerated, unchanged:** control mappings preserved. |
| `site-docs/index.md` | **Regenerated, unchanged:** inventory metrics unchanged with CI's pinned framework. |
| `site-docs/getting-started/deployment-guide.md` | **Regenerated, unchanged:** copy of unchanged deployment guide. |
| `site-docs/reference/changelog.md` | **Regenerated, unchanged:** root changelog copy unaffected by solution-local Unreleased entry. |
| `site-docs/solutions/agent-access-monitor/index.md` | **Regenerated:** documentation list includes the new verification record. Gitignored generated output, not hand-edited. |
| `site-docs/solutions/agent-access-monitor/prerequisites.md`, `flow-configuration.md`, `troubleshooting.md`, `evidence-export.md`, `dataverse-schema.md`, `role-design-append-only.md`, `verification-2026-10-16.md` | **Regenerated:** mirrors source corrections; role-design text unchanged. Gitignored generated outputs. |
| `site-docs/solutions/agent-intake/drift-detection-integration.md` | **Regenerated:** mirrors proposed-adapter clarification. |
| `site-docs/solutions/agent-eligibility-gateway/architecture.md` | **Regenerated:** mirrors native-sharing correction. |
| `site-docs/solutions/copilot-agent-inventory/governance-platform-composition.md` | **Regenerated:** mirrors sharing/lifecycle corrections. |

Implementation surfaces reviewed without modification:

- `agent-access-monitor/scripts/Get-EnvironmentAccessSettings.ps1`,
  `Compare-ZoneCompliance.ps1`, `Test-AgentAccessCompliance.ps1`,
  `Start-AccessValidationRunbook.ps1`, `Invoke-AccessBaselineCapture.ps1`,
  `Export-AgentAccessEvidence.ps1`, and `Test-EvidenceIntegrity.ps1`:
  collection/comparison, scope, persistence, authentication, and export interfaces.
- `agent-access-monitor/scripts/private/AAMClient.psm1`,
  `Get-AAMValidationResults.ps1`, `Get-ExpectedSettings.ps1`,
  `Get-ZoneClassification.ps1`, and `Test-ParameterValidation.ps1`:
  helper contracts remain unchanged by documentation corrections.
- `agent-access-monitor/scripts/agent-access-monitor.psd1`, `aam_client.py`,
  `deploy.py`, `create_dataverse_schema.py`, `create_environment_variables.py`,
  `create_connection_references.py`, and `requirements.txt`: deployment/runtime
  dependencies and schema surface unchanged. This schema script has no
  `--output-docs` generator, so the maintained schema reference was edited directly.
- `cross-solution-integration/scripts/powershell/IntegrationConfig.psm1`:
  AAM identifier/3.8 mapping unchanged.
- `cross-tenant-external-sharing-governance/scripts/governance/Scan-ManagedEnvBotSharingBaseline.ps1`:
  independent local threshold scanner, no per-maker claim or behavior change.
- `copilot-agent-inventory/scripts/discover_agents.py` and
  `create_cai_dataverse_schema.py`: already separate environment policy from
  per-agent posture; no new collector/API implementation added.
- `scripts/build-manifest.py`, `scripts/_backfill-zones.py`,
  `scripts/lint-odata-existence.py`, `scripts/Invoke-CopilotStudioBenchmark.ps1`,
  `scripts/tests/test_build_manifest_partial_controls.py`, and
  `file-upload-security/scripts/fus_client.py`: generator, historical migration,
  schema-validation, benchmark/test, or sibling-client references only.
  No corrected detailed claim depends on changing these scripts.
- Root `CHANGELOG.md`: historical solution summary retained.

## Generators and validation

The local companion checkout currently has 79 controls, while CI pins framework
`v1.6.0` (78 controls). Using the unpinned checkout would introduce unrelated
control-map and homepage drift. Validation used `FRAMEWORK_CONTROLS` pointing to
the existing local `v1.6.0:assessment/manifest/controls.json` git object, exported
to a session-only file. No remote access or framework modification was needed.

Commands run with that environment variable:

```powershell
python scripts\build-manifest.py
python scripts\build-manifest.py --check
python -m mkdocs build --strict
python -m pytest scripts\tests -q
python scripts\validate-language-rules.py
python scripts\verify_commercial_scope.py
python scripts\sync-agent-md-versions.py --check
python scripts\lint-version-drift.py --strict
python scripts\lint-optionset-values.py --strict
```

All checks passed, including 114 repository script tests and the strict MkDocs
build. MkDocs reports existing informational missing-anchor messages in unrelated
intake/message-center pages; these do not fail the strict build.

The manifest generator rebuilds the catalog, detail pages, documentation mirrors,
control map, homepage metrics, root-document mirrors, and controls-covered
artifacts. There is no `build_content_graph.py` or separate content-graph generator
in this repository. No derived output was hand-edited. Generated solution
subpages are gitignored and are rebuilt by CI from the committed sources.

## Facts, assumptions, and remaining limits

- **Verified product facts:** S1-S11 support the product statements above.
- **Local conventions:** zone baselines, severity, broad-sharing alias
  normalization, and viewer-cap categories belong to AAM, not Microsoft.
- **Not established:** a Microsoft-supported collector-host combination for the
  shipped PowerShell requirements, a production-ready replacement Registry
  endpoint, or a tenant's actual access/licensing state. The documentation now
  makes these limits explicit rather than treating historical lab observations as
  vendor support.
- **No live tenant operations:** the existing lab report's real-Managed-
  environment detection/persistence gap is retained. Local checks do not
  establish tenant runtime correctness.
- **Publication boundary:** this record is ready for the trusted parent to use
  in its PR description, including Sources and Downstream artifacts reviewed.
  This worker performed no GitHub writes, push, PR creation, or issue update.
