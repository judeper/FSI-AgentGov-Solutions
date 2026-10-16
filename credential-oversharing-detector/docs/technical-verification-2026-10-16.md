# Technical verification - 2026-10-16

Scope: technical accuracy of the Credential Oversharing Detector README and its downstream implementation, troubleshooting, verification, and evidence guidance. Regulatory mappings and wording are unchanged. This is a live-documentation re-check and local validation, not a tenant deployment or a new live-agent validation.

## Sources

Microsoft Learn search and fetch were used on 2026-10-16, supplemented by the Microsoft release-communications lookup for roadmap ID 566873.

| Source | Claims checked |
|---|---|
| [Roadmap ID 566873](https://www.microsoft.com/en-us/microsoft-365/roadmap?searchterms=566873) | Feature title, publish/share-time behavior, status **In development**, preview target July 2026 and GA target September 2026. Targets are not availability confirmation. |
| [Release plans](https://learn.microsoft.com/en-us/dynamics365/release-plans/) | Release plans stop being published from September 2026; new capabilities move to AI at Work roadmap. |
| [Automatic security scan](https://learn.microsoft.com/en-us/microsoft-copilot-studio/security-scan) | Maker-provided credential warning before publishing is documented independently of roadmap 566873. No per-agent scope extraction contract is established. |
| [Agent (bot) table](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot) | `bots`, `botid`, configuration and connection-related metadata; public table reference does not document the extractor's nested `connectorConfigurations` / `oauthScopes` credential contract. `accesscontrolpolicy` is now documented, contrary to an old domain fact. |
| [Power Platform for Admins V2](https://learn.microsoft.com/en-us/connectors/powerplatformadminv2/) and [Power Platform for Admins](https://learn.microsoft.com/en-us/connectors/powerplatformforadmins/) | Distinct connectors, current names, supported control-plane operations. V2 is `shared_powerplatformadminv2`, not `shared_powerplatformforadmins`. |
| [Connection references](https://learn.microsoft.com/en-us/power-apps/maker/data-platform/create-connection-reference) | Maker portal Solutions navigation, connection binding and ownership/use permissions, asynchronous reference updates. |
| [Power Automate license types](https://learn.microsoft.com/en-us/power-platform/admin/power-automate-licensing/types) | Premium user versus Process capacity licensing, premium/custom connector entitlement and solution-aware flow requirements. Scheduling alone does not require Premium. |
| [Teams connector](https://learn.microsoft.com/en-us/connectors/teams/) | Standard connector; adaptive-card posting and Workflows app requirement. No E3/E5-specific connector requirement was established. |
| [Office 365 connector retirement](https://devblogs.microsoft.com/microsoft365dev/retirement-of-office-365-connectors-within-microsoft-teams/) | Existing troubleshooting retirement dates remain accurate: disablement May 18-22, 2026. The current Power Automate Teams connector is a distinct delivery path. |
| [Workload-identity Conditional Access](https://learn.microsoft.com/en-us/entra/identity/conditional-access/workload-identity) | Location/risk conditions, direct service-principal targeting, `ServicePrincipalsInMyTenant`, Workload ID Premium, exclusions of managed identities and multitenant apps, report-only versus enabled policy, sign-in evaluation. |
| [List service principals](https://learn.microsoft.com/en-us/graph/api/serviceprincipal-list) and [list CA policies](https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-list-policies) | `Application.Read.All` / `Policy.Read.All`, delegated role requirements and current Graph cmdlets. |
| [Federated-credential API](https://learn.microsoft.com/en-us/graph/api/federatedidentitycredential-list) and [PowerShell cmdlet](https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.applications/get-mgapplicationfederatedidentitycredential) | `Get-MgApplicationFederatedIdentityCredential`, Applications module, application object-ID argument. REST API supports read-only `Application.Read.All`. Delegated reads also require application ownership or a supported application-administration/custom role; Security Reader alone is insufficient. App-only reads use application permissions rather than a signed-in user's role. |
| [Application credential guidance](https://learn.microsoft.com/en-us/entra/identity-platform/security-best-practices-for-app-registration) | Managed identity/federation preference, certificates rather than secrets where identity/federation is unavailable. This does not mean every existing COD script implements those paths. |
| [Power Apps PowerShell support](https://learn.microsoft.com/en-us/power-platform/admin/powerapps-powershell) and [admin module](https://learn.microsoft.com/en-us/powershell/powerapps/get-started-powerapps-admin) | `Add-PowerAppsAccount` and `Get-AdminPowerAppEnvironment` exist; the support article explicitly specifies Windows PowerShell 5.x and warns of incompatibility with 6+. COD's PS7 requirement is not proof of module support. |
| [Management app registration](https://learn.microsoft.com/en-us/power-platform/admin/powershell-create-service-principal) and [authentication](https://learn.microsoft.com/en-us/power-platform/admin/programmability-authentication) | `New-PowerAppManagementApp`, administrator registration context, service principal cannot register itself, supported operation limitations. |
| [Application users](https://learn.microsoft.com/en-us/power-platform/admin/manage-application-users) | Dataverse application users can be unlicensed and receive security roles; no universal per-user/per-app SKU requirement for the application user. |
| [Power Platform preview terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/) | Referenced terms remain accessible. No legal interpretation was performed. |

## Discrepancies and propagation

1. **Licensing:** E3/E5 was stated as a Teams-alert requirement without a connector-specific basis. Replaced it with Teams/channel access and documented Premium/Process rights for Dataverse flows. Added the Workload ID Premium prerequisite for CA policy changes.
2. **Telemetry/availability conflation:** Roadmap 566873 describes safe-sharing controls, not the OAuth-scope feed assumed by the extractor. Removed instructions to enable an undocumented feature for scope extraction. README, prerequisites, flow validation, troubleshooting, lab acceptance and manifest verification now distinguish missing coverage from a passing scan.
3. **Incorrect V2 identifier:** The setup script labeled `shared_powerplatformforadmins` as V2. New references now use `shared_powerplatformadminv2`. Existing references still skip creation; the flow/troubleshooting guides explain manual migration and dependent-action review. Offline regression tests cover exact payloads, unchanged existing-reference behavior, and no-call dry runs.
4. **Graph prerequisites:** Existing CA/auth helpers call Graph; the previous documentation called Graph future-only and prescribed `ServicePrincipal.Read.All`. Documented actual helpers, separate session setup, `Application.Read.All` and `Policy.Read.All`, and operation-specific delegated roles. Federated-credential reads require application ownership or a supported application-administration/custom role, not merely the CA reader role. The auth helper suppresses failed credential lookups; its `NoCredentials` / "No action required" output requires independent confirmation of successful enumeration.
5. **CA coverage:** Workload-identity CA does not cover managed identities or multitenant applications. The current helper is heuristic inventory, not complete effective-policy evaluation: state, exclusions, filters and tenant-wide selectors need manual verification. Guidance and acceptance criteria now say so; this task does not rewrite that evaluator.
6. **Host/authentication overstatement:** PS7 script requirements do not override Microsoft's PS5.x module support guidance. The main scanner/extractor remain client-secret-only dev paths despite general managed-identity recommendations. Documented these limitations instead of claiming a supported production host/auth combination.
7. **Execution/evidence:** Main-scan dry run, automatic helper invocation and credential remediation were overimplied. Clarified actual switches, independent helper execution, baseline population, and the policy-only auto-remediation flag. Quick Start now supplies persistence parameters. Evidence must include source coverage; hashing alone cannot establish completeness.
8. **Stale domain fact:** Live Microsoft table metadata includes `bot.accesscontrolpolicy`; removed the obsolete absence assertion from domain facts without altering scanner queries.
9. **Evidence-field provenance:** Corrected the canonical violation-column description to attribute approved OAuth-scope writes only to `Compare-OAuthScopeBaseline.ps1`. `Test-AgentAuthMethod.ps1` does not populate either scope field; empty scope fields on its `AUTH-*` violations are not a failed scope-baseline capture. Regenerated the schema reference and added offline regressions for writer attribution and generated-document consistency.

The feature name, roadmap targets and In-development status remain unchanged; their checked date and the README **Last Verified** marker are now 2026-10-16. There are no README screenshots to refresh. Zone thresholds, six violation types, option-set values and local evidence/hash formats are repository policy/implementation, not Microsoft product limits.

## Downstream artifacts reviewed

Paths below are repository-relative. A grouped row names each artifact with the same disposition.

| Artifact | Disposition and reason |
|---|---|
| `credential-oversharing-detector/README.md` | Changed: current verification stamp, bounded technical claims, licensing, persistence examples, references. |
| `credential-oversharing-detector/manifest.yaml` | Changed: checked date and verification gate, feeding generated site detail and lock-file verification text. Version, status, controls and regulatory mappings are unchanged. |
| `credential-oversharing-detector/docs/prerequisites.md` | Changed: licensing, host/auth gaps, Graph helper permissions, telemetry caveat. |
| `credential-oversharing-detector/docs/flow-configuration.md` | Changed: V2 identity/migration, data-source gate, pagination guidance, positive/negative validation and evidence coverage. |
| `credential-oversharing-detector/docs/troubleshooting.md` | Changed: missing telemetry is inconclusive, host/V2/Graph diagnosis, app-only versus delegated permission distinction. |
| `credential-oversharing-detector/docs/technical-verification-2026-10-16.md` | Added: source-backed discrepancies, downstream inventory, generator input provenance and local validation results for the publishing parent. |
| `credential-oversharing-detector/LAB-VALIDATION.md` | Changed: dated superseding caveat and current acceptance gate; original test date/results retained as history. |
| `credential-oversharing-detector/.ralph-config.json` | Changed: corrected V2 identity, Graph helper behavior and bot metadata fact. |
| `credential-oversharing-detector/CHANGELOG.md` | Changed: new Unreleased re-verification entry. Older entries remain historical; no retrospective claim of new tenant testing. |
| `credential-oversharing-detector/scripts/create_cod_connection_references.py` | Changed: actual V2 connector identity and bounded description. |
| `scripts/tests/test_cod_connection_references.py` | Added: offline regression coverage of actual setup function and outgoing payloads. |
| `credential-oversharing-detector/scripts/create_cod_dataverse_schema.py` | Changed: corrected the canonical approved-scope description to name only the actual scope-baseline writer. No column names, types, required levels or runtime behavior changed. |
| `scripts/tests/test_cod_schema_docs.py` | Added: offline regressions verify both violation scope descriptions name the scope-baseline writer, not the auth helper, and the committed schema reference matches its generator. |
| `credential-oversharing-detector/scripts/create_cod_environment_variables.py` | Unchanged: environment-variable creation does not depend on corrected feature timing, connector identity, evidence descriptions or Graph permissions. |
| `credential-oversharing-detector/docs/dataverse-schema.md` | Regenerated from the corrected canonical schema script, not hand-edited. The scope fields retain their existing space-separated format. |
| `credential-oversharing-detector/scripts/governance/Get-AgentConnectorScope.ps1`, `Invoke-CredentialScan.ps1`, `Test-CredentialCompliance.ps1` (same directory) | Unchanged: documented their existing parsing, persistence, host/auth and coverage limitations rather than inventing a supported telemetry API or broadening this task into an authentication rewrite. |
| `credential-oversharing-detector/scripts/governance/Get-WorkloadIdentityCAPolicy.ps1` | Changed help only: remove the incorrect managed-identity CA applicability claim and bound the inventory's effective-coverage limitations. Evaluation behavior is unchanged. |
| `credential-oversharing-detector/scripts/governance/Test-AgentAuthMethod.ps1`, `Compare-OAuthScopeBaseline.ps1` (same directory) | Unchanged: inspected Graph calls and baseline reads. Current docs explicitly bound helper scope and manual verification; evaluator changes are not implied by this re-check. |
| `credential-oversharing-detector/scripts/governance/Get-ExpectedCredentialPolicy.ps1`, `Export-CredentialEvidence.ps1`, `Test-EvidenceIntegrity.ps1` (same directory) | Unchanged: local policy/evidence helpers do not establish upstream availability. Added coverage qualifications to the consuming evidence instructions instead. |
| `credential-oversharing-detector/templates/zone-credential-policy.json`, `credential-oversharing-detector/templates/adaptive-card-credential-alert.json`, `credential-oversharing-detector/controls-covered.json` | Unchanged: local thresholds/card schema/control mappings; no corrected Microsoft availability, licensing or connector-ID claim to propagate. |
| `credential-oversharing-detector/scripts/requirements.txt` | Unchanged: no dependency changes needed for the connector constant or documentation. |
| `solutions.json` | Regenerated: corrected manifest verification criteria. Its schema/version and control coverage remain unchanged. |
| `site-docs/solutions/credential-oversharing-detector/index.md`, `dataverse-schema.md`, `flow-configuration.md`, `prerequisites.md`, `troubleshooting.md`, `technical-verification-2026-10-16.md` (same generated directory) | Regenerated: the manifest-based detail page carries corrected verification criteria and links to copied sub-docs, including this dated verification record. The generator does not copy the README body or its Last Verified marker into that page; the source README owns the marker. Gitignored outputs are not hand-edited or committed. |
| `README.md`, `site-docs/solutions/index.md`, `site-docs/reference/control-mapping.md`, `site-docs/index.md` | Regenerated/unchanged: catalog descriptions, counts, status, zones and control mappings are unaffected. |
| `site-docs/getting-started/deployment-guide.md`, `site-docs/reference/changelog.md` | Generator-managed root-document copies; unchanged because the source deployment guide/root changelog do not restate corrected claims. |
| `AGENTS.md`, `.github/copilot-instructions.md`, `DEPLOYMENT-GUIDE.md`, `mkdocs.yml`, `.squad/skills/repo-context.md` | Unchanged: solution catalog/routing/navigation references only; no version bump or new nav item needed (the verification record is linked from the README). |
| `copilot-billing-governance/manifest.yaml` | Unchanged: comment refers to connector governance as a boundary, not product availability, licensing or scope telemetry. |
| `agent-intake/research/02-question-catalog-report-claude.md`, `agent-intake/research/02-question-catalog-research-prompt.md` | Unchanged: historical intake research rather than deployed COD validation instructions; links/identifiers do not depend on the corrected API/licensing claims. |
| `agent-sharing-access-restriction-detector/docs/technical-verification-2026-10-16.md` | Unchanged: cross-solution review inventory, not a restatement of the corrected COD claims. |
| Root `CHANGELOG.md`, `scripts/_backfill-zones.py` | Unchanged: historical release/catalog and one-off zone backfill references; no corrected current claim. |

Discovery covered the slug, title, roadmap ID, credential-oversharing wording, linked documents, all nine governance scripts, three setup scripts, templates, manifest verification and generated navigation. `scope-drift-monitor/README.md`, `agent-sharing-access-restriction-detector/README.md` and `content-moderation-monitor/README.md` are unchanged: the README links describe boundaries only, and these documents do not inherit COD's corrected availability/licensing/telemetry claims. No content-graph generator exists in this repository.

## Generator commands and outputs

```text
python credential-oversharing-detector\scripts\create_cod_dataverse_schema.py --output-docs
$env:FRAMEWORK_CONTROLS = "<path-to-extracted-canonical-controls.json>"
python scripts\build-manifest.py
python scripts\build-manifest.py --check
python -m mkdocs build --strict
```

The schema command regenerates `credential-oversharing-detector/docs/dataverse-schema.md`. The manifest generator emits `solutions.json`, catalog/hero/control-mapping pages, solution detail pages and copied sub-docs, plus root deployment-guide/changelog mirrors. MkDocs renders the ignored `site/` tree. Generated content is derived from canonical sources; no generated page was manually edited.

**Framework input:** The default sibling checkout has unrelated control-count/title changes. To preserve this repository's existing 78-control baseline and avoid altering control mappings, generation and determinism checks used the exact canonical `assessment/manifest/controls.json` blob from local framework revision `f1c132af96de5e9324e4283cca11da88ef6e5925`, extracted with `git show` to session storage and supplied via `FRAMEWORK_CONTROLS`. The IDs and titles match the committed control-mapping page exactly. No framework source was edited or inferred. A default build using the newer sibling input also ran initially; its unrelated generated mapping/hero drift was removed by regeneration with the matching input, not by hand-editing outputs. CI using a newer framework revision may independently require baseline reconciliation; this task does not perform that out-of-scope update.

## Initial implementation validation

These results were recorded before the PR review follow-up. The PR description records the follow-up checks separately.

- Repository-wide Python suite: **1,324 passed, 2 skipped**, with one existing pytest fixture-deprecation warning. Shared suite separately: **117 passed**, including the three new connection-reference regressions.
- Whole-repository Ruff, language rules, commercial-scope validation and `git diff --check`: passed.
- Schema regeneration, manifest generation/determinism check with the matching framework input, and strict MkDocs build: passed. MkDocs reports existing informational navigation/anchor notices outside COD.
- All nine solution PowerShell scripts parse successfully. Solution PSScriptAnalyzer reports zero Warning/Error findings. No solution-specific Pester files exist.
- OData column lint: zero violations. OData existence lint exits successfully but reports **17 existing findings**, including COD's cross-solution ELM `fsi_zoneclassification` reference; these are not new schema changes and are not represented as a clean diagnostic baseline.

## Facts, assumptions and unknowns

**Verified facts:** The live Microsoft sources above and local implementation establish the documented product boundaries, corrected connector identity and actual script behavior.

**Assumptions requiring tenant evidence:** A target tenant supplies the nested configuration fields expected by COD, identities are correctly associated with agents, and approved/actual scope baselines are populated and current.

**Not established by this re-check:** Public availability of roadmap 566873, a supported real-agent OAuth telemetry contract, supported PS7 Power Apps module execution, complete/effective CA evaluation, or production-ready identity support in the main scanner. No live tenant, portal, credential or GitHub authentication operations were performed.
