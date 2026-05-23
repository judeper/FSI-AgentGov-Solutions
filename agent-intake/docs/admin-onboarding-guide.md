# Admin onboarding guide — agent-intake v1.0.0-preview

**Audience:** Power Platform and Microsoft 365 administrators deploying `agent-intake` for a customer.

**Use this guide with:** [`pilot-deployment-runbook.md`](./pilot-deployment-runbook.md), [`orchestrator-architecture.md`](./orchestrator-architecture.md), [`flow-build-prerequisites.md`](./flow-build-prerequisites.md), [`flow-configuration.md`](./flow-configuration.md), [`reviewer-app-build.md`](./reviewer-app-build.md), [`identity-records-automation.md`](./identity-records-automation.md), [`mrm-integration.md`](./mrm-integration.md), and [`drift-detection-integration.md`](./drift-detection-integration.md).

## 1. Who this guide is for

This handbook is for the customer admin who owns the first real deployment of `agent-intake` in a lab, pilot, or early production-ready environment.

You are probably one of these people:

- a **Power Platform Admin** wiring Dataverse, Power Pages, solution components, and flows
- a Microsoft 365 platform admin coordinating Teams, Microsoft Graph, and Purview dependencies
- an AI governance platform owner who must explain how the solution works to InfoSec, Privacy, Compliance, Legal, and MRM

If you only need a quick pilot checklist, start with [`pilot-deployment-runbook.md`](./pilot-deployment-runbook.md). If you are the person expected to build, configure, smoke-test, and operate the solution, stay here.

## 2. What you're getting

`agent-intake` v1.0.0-preview is a full preview slice of the intake workflow, not just the original Express path.

| Feature area | What ships in this preview | Primary source |
|---|---|---|
| Three-path intake | Express, Standard, Full, and DefaultDeny routing | [`classification-rules.md`](./classification-rules.md) |
| Maker surface | Progressive-disclosure Power Pages form design | [`portal-configuration.md`](./portal-configuration.md) and [`maker-form-progressive-disclosure.md`](./maker-form-progressive-disclosure.md) |
| Sponsor approval | Teams sponsor card for Express | [`flow-configuration.md`](./flow-configuration.md) |
| Reviewer board | Standard / Full parallel review and quorum | [`reviewer-app-build.md`](./reviewer-app-build.md) and [`flow-configuration.md`](./flow-configuration.md) |
| Decision evidence | Immutable decision pack and audit events | [`flow-configuration.md`](./flow-configuration.md#flow-8-fsi-intake-decision-pack-writer) |
| Appeal path | Denial appeal with lineage preservation | [`flow-configuration.md`](./flow-configuration.md#flow-11-fsi-intake-denial-appeal) |
| Identity handoff | Microsoft Entra Agent ID blueprint and identity minting | [`identity-records-automation.md`](./identity-records-automation.md) |
| Downstream governance | Registry, drift, and optional MRM handoff | [`drift-detection-integration.md`](./drift-detection-integration.md) and [`mrm-integration.md`](./mrm-integration.md) |
| Repeatable deployment | `deploy.ps1`, smoke test, seed data, teardown | [`orchestrator-architecture.md`](./orchestrator-architecture.md) |

### ADR highlights every admin should know

These are the design decisions customers usually ask about first:

| Decision | Why you should care | Source |
|---|---|---|
| **Express requires all six triggers = No and Zone 3** | Explains why many apparently simple requests still route out of Express | [ADR-002](./decisions.md#adr-002--express-eligibility--t1t6-all-no--tier-3--zone-3) |
| **Cross-border defaults to deny until Privacy override** | This is the most common “why was it denied?” question in pilots | [ADR-005](./decisions.md#adr-005--default-deny-when-maker-country-differs-from-data-residency-country) |
| **7-year retained decision evidence** | Drives retention label setup and records conversations | [ADR-006](./decisions.md#adr-006--7-year-immutable-retention-via-purview-fsi-agentintake-7yr-label) |
| **Sponsor 1-click is Express-only** | Prevents admins from reusing the Express card for Standard or Full sign-off | [ADR-007](./decisions.md#adr-007--sponsor-1-click-is-sufficient-finra-3110-evidence-for-express-only) |
| **Sponsor self-approval is blocked** | Explains a common default-deny path during testing | [ADR-008](./decisions.md#adr-008--sponsor-cannot-self-approve) |
| **Trigger changes force re-review** | Matters for post-approval updates and drift handling | [ADR-009](./decisions.md#adr-009--major-modification-triggers-fresh-review-minor-does-not) |
| **Appeals preserve lineage** | Important for audit and customer change management | [ADR-010](./decisions.md#adr-010--denial-appeal-one-re-submission-allowed) |
| **Reviewer app export is permitted** | Explains why a managed model-driven app package can exist for the reviewer UI | [ADR-011](./decisions.md#adr-011--model-driven-app-zip-is-permitted-under-repo-solution-content-policy) |

## 3. Customer responsibility note

This repository follows a strict solution-content boundary:

- it ships **documentation**, **scripts**, and **templates**
- it does **not** ship exported Power Automate flow JSON, Canvas app packages, connection-reference exports, or environment-variable exports as customer deliverables
- customers build the 12 flows manually by following [`flow-configuration.md`](./flow-configuration.md)

That boundary matters for two reasons:

1. it keeps tenant-specific bindings, approvals, and connection choices in the customer's control
2. it avoids brittle runtime artifacts that are hard to validate across environments

The solution also does **not** make policy decisions for the customer. The customer still owns:

- DLP policy
- data-classification policy
- country-routing policy
- sponsor and reviewer assignment
- legal interpretation of regulatory obligations
- production change management

In other words, `agent-intake` supports compliance with the customer's governance program when it is configured and operated correctly. It does not replace that program.

## 4. Prerequisites

### Tooling and local workstation prerequisites

| Requirement | Minimum | Why it is required |
|---|---|---|
| PowerShell | 7.0+ | `deploy.ps1`, `smoke_test.ps1`, retention-label setup, shell provisioning |
| Power Platform CLI (`pac`) | Current supported release | Solution shell, Power Pages checks, environment selection |
| Azure CLI (`az`) | Current supported release | Default `AzCli` auth mode and access-token acquisition |
| Python | 3.10+ (3.11+ recommended) | Schema, identity, MRM, and helper scripts |
| Git | Current supported release | Repo clone and upgrade workflows |
| ExchangeOnlineManagement | 3.2.0+ | Purview retention-label automation on Windows |
| Python packages | `requests`, `msal`, `pyyaml`, `azure-identity`, `jsonschema` | Script dependencies used by deploy, handoff, and validation steps |

### Environment and tenant prerequisites

| Requirement | Why it is required |
|---|---|
| Power Platform environment with Dataverse | Core data model and flows live here |
| Power Pages site in the same environment | Maker-facing intake form |
| Teams enabled | Sponsor and reviewer adaptive cards |
| Microsoft Entra Agent ID feature enabled | Agent ID minting after approval |
| Microsoft Purview Records Management | Retention labels for decision evidence |
| Optional `model-risk-management-automation` deployment | Full-path Tier-1 MRM handoff |
| Optional downstream drift solutions | Live post-approval monitoring and feedback loop |

### Roles and access

| Role | Typical reason |
|---|---|
| **Power Platform Admin** | Solution shell, Dataverse, Power Pages, flow build |
| **System Administrator** or **System Customizer** in Dataverse | Reviewer app and solution-component changes |
| **Purview Compliance Admin** (or equivalent records role) | `Connect-IPPSSession`, `Get-ComplianceTag`, `New-ComplianceTag` |
| **Cloud Application Administrator** or **Entra Global Admin** | Agent ID consent and blueprint setup when needed |
| **Teams / Microsoft 365 admin** | Connector readiness and notification routing |
| **Reviewer-board security-role assigner** | InfoSec / Privacy / Compliance / Legal / MRM role setup |

### Optional but strongly recommended dependencies

- [`model-risk-management-automation`](../../model-risk-management-automation/README.md) for Tier-1 MRM handoff
- `agent-registry-automation` for live approved-request registration
- drift-monitoring peer solutions referenced in [`drift-detection-integration.md`](./drift-detection-integration.md)

## 5. First deployment

### Recommended first-run command

From the `agent-intake` solution folder:

```powershell
Set-Location .\agent-intake\scripts
pwsh .\deploy.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com -SeedTestData
```

For unattended automation, prefer managed identity when available:

```powershell
pwsh .\deploy.ps1 `
  -EnvironmentUrl https://<your-env>.crm.dynamics.com `
  -AuthMode ManagedIdentity `
  -SeedTestData
```

### What the orchestrator does

The orchestrator stages are documented in [`orchestrator-architecture.md`](./orchestrator-architecture.md#2-stages).

| Stage | What it does | Typical first-run timing |
|---|---|---:|
| Stage 0 | Preflight tooling, PAC, Azure CLI, auth, connectivity | 1-2 min |
| Stage 1 | Deploy or validate schema and option sets | 1-2 min |
| Stage 2 | Create or validate the unmanaged solution shell | ~1 min |
| Stage 3 | Identity and records setup checks | 1-3 min |
| Stage 4 | Maker-surface validation and Power Pages checks | ~1 min |
| Stage 5 | Reviewer app provisioning or validation | 1-2 min |
| Stage 6 | Hydrate solution environment variables from policy and overrides | <1 min |
| Stage 7 | Smoke test | ~1 min |
| Stage 8 | Seed deterministic demo data and rerun seeded smoke gate | 1-2 min |

A well-prepared lab usually finishes in about **10 minutes**. The first run may take longer if Power Pages or Agent ID prerequisites still need manual work.

### Expected output on success

Look for all of the following:

- exit code `0`
- a stage summary where each required stage is `Success`
- a structured log file named like `agent-intake-deploy-<timestamp>.log`
- a smoke pass at Stage 7
- seeded scenario creation and a seeded smoke pass at Stage 8 if `-SeedTestData` was used

### Expected output when manual work is still needed

The orchestrator intentionally prints `MANUAL STEP REQUIRED:` messages for gaps it cannot close automatically, especially around classic Power Pages steps and some custom-connector edges. That is not a fatal error by itself. Complete the manual step, then rerun `deploy.ps1`.

### First-run recommendations

- Do **not** use `-SkipSmoke` on the first deployment.
- Keep `-SeedTestData` on for the first lab so you can validate Express, Standard, Full, and deny paths quickly.
- Save the structured log with the change record for the deployment.

## 6. Configuring `policy-lookup-tables.yaml`

`templates/policy-lookup-tables.yaml` is the shipped policy surface for routing, quorum, reviewer SLAs, retention labels, and handoff behavior. Read it before your first deployment, even if you keep the defaults.

### Top-level keys and what they control

| Key | What it controls | Common customer override |
|---|---|---|
| `schema_version` | Policy document version marker | Leave as shipped unless you control a customer fork |
| `last_updated_utc` | Timestamp for policy update tracking | Update when you change the file |
| `data_residency` | Cross-border default action and privacy override behavior | Allow-list country pairs or change the default action |
| `infosec_sampling` | Express passive-sample policy | Increase or decrease the sample rate |
| `sponsor_sla` | Sponsor response, escalation, and timeout timing | Tighten or loosen review windows |
| `reviewer_routing` | Per-role SLA, escalation contact, and condition policy | Replace placeholder contacts with real shared mailboxes |
| `quorum` | Minimum approvals and total board size by tier | Example: change Tier 1 from 3-of-5 to 4-of-5 |
| `mrm` | MRM target and fallback behavior | Point Full-path handoff to a different queue |
| `parallel_routing` | Sequential vs parallel routing model per tier | Keep as shipped in most pilots |
| `retention_labels` | Label names used by the solution | Rename to the customer's Purview labels |
| `managed_environment` | Required environment posture by tier | Enforce stricter environment discipline |
| `dlp_connector_group` | DLP connector policy by tier | Tighten Tier 3 if the customer is conservative |
| `connector_allowlist` | Connector baseline for decision-pack and drift logic | Add the customer-approved connector list |
| `zone_routing` | Role expectations by zone | Add or tighten role requirements |
| `audience_to_zone` | Maps the audience answer to a zone | Adjust if the customer wants department use treated as Zone 1 |
| `modification_cutoff` | Re-review expectations after approval | Tune what counts as minor or major |
| `denial_appeal` | Appeal caps by path | Tighten or loosen resubmission count |
| `sponsor_attestation` | Card wording and retention-years framing | Replace placeholder wording with the firm's approved text |
| `deferred` | Work still intentionally not implemented as a fully automated experience | Usually read-only context |

### Common override examples

If the customer wants a stricter Tier-1 quorum:

```yaml
quorum:
  tier_1:
    minimum_approvals: 4
    total_reviewers: 5
```

If the customer already allows a specific country pair:

```yaml
data_residency:
  default_action: "deny"
  privacy_override_enabled: true
  allowed_country_pairs:
    - maker: "US"
      data: "CA"
```

If the customer uses different retention-label names:

```yaml
retention_labels:
  tier_1: "AI-Intake-7yr"
  tier_2: "AI-Intake-7yr"
  tier_3: "AI-Intake-7yr"
  decision_log: "AI-Intake-7yr-WORM"
```

### Practical guidance

- Treat the shipped values as **placeholders for a customer pilot**, not final production policy.
- Keep one reviewed copy of the YAML in source control and one approved copy in customer change management.
- Rerun `deploy.ps1` after material YAML changes so policy hydration and smoke checks stay aligned.

## 7. Hydrating environment variables

The orchestrator writes solution environment variables in Stage 6. The baseline list is documented in [`flow-build-prerequisites.md`](./flow-build-prerequisites.md#4-populate-solution-environment-variables).

### Solution environment variables

| Solution env var | What to set | Where to source it |
|---|---|---|
| `fsi_intake_powerplatformenvironmenturl` | Current Dataverse environment URL | The actual environment URL you are deploying into |
| `fsi_intake_makerportalurl` | Public maker portal URL | Final Power Pages URL for `/agent-intake` |
| `fsi_intake_reviewerappurl` | Reviewer model-driven app URL | The appmodule URL or friendly customer app link |
| `fsi_intake_mrmtargetenv` | MRM target environment or wrapper endpoint | Same environment, or the target used by `model-risk-management-automation` |
| `fsi_intake_driftdetectorenv` | Drift-detector endpoint or environment | The downstream drift target used by peer solutions |
| `fsi_intake_retentionlabelid` | Purview label identifier or wrapper identifier | Customer Purview label ID or label name strategy |
| `fsi_intake_sponsorbackupgroup` | Backup sponsor group or mailbox | Customer group used for sponsor timeout and escalation fallback |

### What the orchestrator does if values are missing

Per [`deploy.ps1`](../scripts/deploy.ps1), the orchestrator will:

- use the environment URL for `fsi_intake_powerplatformenvironmenturl`
- use the current environment or existing value when possible for MRM and drift targets
- fall back to placeholders for the maker portal URL, reviewer app URL, and sponsor backup group when the real value is not known yet

That makes the first run easier, but you should replace placeholders before any real pilot.

### Runtime override environment variables recognized by `deploy.ps1`

These are **host environment variables**, not solution environment variables. They let you inject customer-specific values without editing the script.

| Runtime variable | Typical use |
|---|---|
| `AGENT_INTAKE_MAKER_PORTAL_URL` | Override the maker portal URL |
| `AGENT_INTAKE_REVIEWER_APP_URL` | Override the reviewer app URL |
| `AGENT_INTAKE_MRM_TARGET_ENV` | Override the MRM target |
| `AGENT_INTAKE_DRIFT_DETECTOR_ENV` | Override the drift target |
| `AGENT_INTAKE_RETENTION_LABEL_ID` | Override the retention label identifier |
| `AGENT_INTAKE_SPONSOR_BACKUP_GROUP` | Override the sponsor backup group |
| `AGENT_INTAKE_GRAPH_CUSTOM_CONNECTOR_API_ID` | Reuse an existing Microsoft Graph custom connector |
| `AGENT_INTAKE_PURVIEW_ADMIN_UPN` | Drive retention-label setup under a known admin identity |
| `AGENT_INTAKE_BLUEPRINT_SPONSOR_UPN` | Set the blueprint sponsor used by Agent ID setup |
| `AGENT_INTAKE_AGENT_BLUEPRINT_ID` | Supply a known blueprint ID for Agent ID minting |
| `AGENT_INTAKE_LIVE_AGENT_ID` | Opt into live Agent ID creation during seeded tests |

## 8. Building the 12 flows

The repository does not ship exported flow artifacts. Build all flows manually in the **FSIAgentIntake** unmanaged solution shell created by `provision_solution_shell.ps1` or by Stage 2 of `deploy.ps1`.

Read these first:

1. [`flow-build-prerequisites.md`](./flow-build-prerequisites.md)
2. [`flow-configuration.md`](./flow-configuration.md)
3. [`portal-configuration.md`](./portal-configuration.md)
4. [`maker-form-progressive-disclosure.md`](./maker-form-progressive-disclosure.md)

### Rough effort estimate

- **Experienced Power Platform admin in a prepared tenant:** 2-4 hours
- **First-time tenant build with policy/legal reviews still happening:** 1-2 days elapsed time

### Build order

Follow the build order from [`flow-configuration.md`](./flow-configuration.md#logical-build-order).

| Order | Flow | Purpose |
|---|---|---|
| 1 | `fsi-intake-presubmit-classifier` | Synchronous routing contract for the maker form |
| 2 | `fsi-intake-router` | Writes path, tier, zone, quorum, and status |
| 3 | `fsi-intake-sponsor-card` | Express sponsor surface |
| 4 | `fsi-intake-parallel-reviewers` | Standard / Full reviewer fan-out |
| 5 | `fsi-intake-reviewer-decision-handler` | Captures reviewer decisions and recomputes quorum |
| 6 | `fsi-intake-mrm-handoff` | Full Tier-1 handoff into MRM |
| 7 | `fsi-intake-decision-pack-writer` | Immutable evidence writer |
| 8 | `fsi-intake-registry-handoff` | Agent ID minting and registry handoff |
| 9 | `fsi-intake-drift-handoff` | Downstream drift baseline |
| 10 | `fsi-intake-denial-appeal` | Appeal lineage |
| 11 | `fsi-intake-escalation` | Overdue reviewer escalation |
| 12 | `fsi-intake-retention-tagger` | Retention evidence stamping |

### Practical build tips

- Bind connection references **before** saving the first flow.
- Build inside the solution shell so environment variables and connection references travel together.
- Keep the flow payload keys unchanged even if the customer wants different wording on the card.
- If PAC CLI leaves a Power Pages gap, finish the manual work in the maker portal, then rerun `deploy.ps1`.

## 9. Smoke testing

### Baseline validation

Run the smoke test after the first deploy and after any material config change.

```powershell
Set-Location .\agent-intake
pwsh .\scripts\smoke_test.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com
```

### Seeded path validation

Use this after `deploy.ps1 -SeedTestData` or after a standalone seed run:

```powershell
pwsh .\scripts\smoke_test.ps1 `
  -EnvironmentUrl https://<your-env>.crm.dynamics.com `
  -IncludeSeededDataChecks `
  -PathScope All
```

### How to read the output

A healthy smoke run should confirm:

- all nine Dataverse tables exist
- required option sets exist
- environment variables are hydrated
- key columns exist
- the docs language scan is clean
- seeded scenarios pass for Express, Standard, Full, and the deny paths when you include seeded checks

Use `-PathScope Express`, `Standard`, or `Full` when you are troubleshooting one path without rechecking the entire seeded set.

## 10. Ongoing operations

### Drift monitoring

Once requests are approved and handed off, ongoing governance moves to peer solutions. Review [`drift-detection-integration.md`](./drift-detection-integration.md) so you know which fields downstream tools expect:

- origin intake ID
- approved tier and zone
- declared audience
- declared data sources
- sponsor UPN
- Microsoft Entra Agent ID
- reviewer attestation chain for Standard and Full

If the customer deploys `unrestricted-agent-sharing-detector`, `scope-drift-monitor`, `agent-access-monitor`, or `agent-365-lifecycle-governance`, make sure those teams know the handoff contract is live.

### Retention-label management

The shipped labels are `FSI-AgentIntake-7yr` and `FSI-AgentIntake-7yr-WORM`.

Operational reminders:

- keep the label names in Purview aligned with `retention_labels` in the policy YAML
- do not remove shared Purview labels casually; the orchestrator intentionally leaves them in place during teardown
- verify the decision-pack writer and retention tagger still reference the intended label after any rename

### Agent ID lifecycle

The approval flow mints or references a Microsoft Entra Agent ID after approval. Operationally, you should track:

- the blueprint ID used for the environment
- whether the tenant still has the Agent ID feature enabled
- whether seeded tests are using synthetic IDs or live IDs
- the downstream registry record ID linked to each approved request

If a tenant feature gate is still closed, the solution can proceed through most setup steps and then finish the identity handoff later once the tenant flag is available.

### Sponsor backup designation

Keep `fsi_intake_sponsorbackupgroup` current when managers leave, team structures change, or the customer wants a formal backup approver path.

### Escalation policy tuning

Review these settings periodically:

- `sponsor_sla`
- `reviewer_routing`
- `quorum`
- `denial_appeal`
- `data_residency`

A good pilot habit is to review them after the first 10-20 real requests rather than waiting for production.

## 11. Reviewer board changes

When the customer wants a new reviewer role, follow the pattern documented in [`reviewer-app-build.md`](./reviewer-app-build.md#10-customer-override).

At a minimum you must:

1. extend the `fsi_intake_reviewerrole` choice set
2. create the Dataverse security role for that reviewer group
3. add a role-scoped queue view in the reviewer app
4. update `templates/policy-lookup-tables.yaml > reviewer_routing`
5. add role-specific attestation text to `reviewer-notification-card.json`
6. rerun `provision_reviewer_app.ps1` or rebuild the reviewer app components manually
7. retest Standard and Full routing plus the reviewer decision handler

Do not stop after the choice-set change. The flow, card, app, and security model all need to agree.

## 12. Customer-specific tailoring

Most customer tailoring should happen in configuration and tenant setup, not in code forks.

### DLP per zone

Use these policy areas together:

- `dlp_connector_group`
- `connector_allowlist`
- `managed_environment`

A common pattern is to keep Tier 1 and Tier 2 inside `businessDataOnly`, while allowing a narrower approved set for Tier 3 personal agents.

### Environment topology

Customers often tailor by:

- separate dev / test / prod environments
- one maker portal URL per environment
- one reviewer app URL per environment
- different MRM or drift targets per environment

If you do this, keep the solution environment variables environment-specific and avoid hard-coding URLs in the flows.

### Sensitive-data classifications and residency

Customers usually tailor:

- label names
- output classification assumptions
- country allow-lists
- Privacy override ownership
- whether department scope is Zone 2 or Zone 1

Make those changes in policy, then rerun deployment and smoke validation.

## 13. Upgrading

Because this is preview content, expect future version bumps to tighten the schema, reviewer logic, or handoff payloads.

### Safe upgrade pattern

1. review the updated docs and change notes
2. apply changes in a lower environment first
3. refresh `policy-lookup-tables.yaml` with customer overrides
4. rerun `deploy.ps1`
5. rerun smoke tests
6. rerun seeded test data if the customer uses the demo lab

### When `-Teardown` makes sense

`deploy.ps1 -Teardown` is best for:

- disposable lab tenants
- early pilot rebuilds before regulated records matter
- schema-reset exercises during development

It is **not** the right first choice for an environment where retained decision evidence must be preserved. The orchestrator is idempotent, so prefer a re-run over teardown when you are fixing a partial failure.

### When you still might use teardown for a major schema change

If a future release introduces a breaking schema revision and the environment is still a disposable lab, the fastest path may be:

1. export any local notes you want to keep
2. run `deploy.ps1 -Teardown`
3. rerun `deploy.ps1 -SeedTestData`
4. rebuild any manual Power Pages pieces the orchestrator could not recreate automatically

## 14. Troubleshooting

### Exit-code matrix

The deploy exit codes are defined in [`orchestrator-architecture.md`](./orchestrator-architecture.md#5-exit-code-matrix).

| Exit code | Stage | Common causes | Typical remediation |
|---|---|---|---|
| `10` | Preflight | Missing `pac`, `az`, PowerShell module, Python package, or auth context | Install the missing tool or module, sign in again, rerun |
| `20` | Schema | Dataverse permissions, schema drift, or table/option-set creation failure | Rerun the schema script directly, fix the permission issue, rerun deploy |
| `30` | Solution shell | Solution shell missing, connection-reference setup failed, or PAC environment mismatch | Confirm the schema exists, confirm `pac env who`, rerun Stage 2 via deploy |
| `40` | Identity and records | Purview label failure, Agent ID consent issue, feature gating, missing blueprint | Use the manual fallback in [`identity-records-automation.md`](./identity-records-automation.md), then rerun |
| `50` | Maker surface | Power Pages site missing, PAC classic-site limitation, maker portal URL unresolved | Complete the manual portal steps, populate the URL, rerun |
| `60` | Reviewer app | Missing rights, spec mismatch, or reviewer app provisioning failure | Check reviewer roles and Dataverse rights, rerun app provisioning |
| `70` | Policy hydration | Invalid YAML, unresolved override, or environment-variable write failure | Fix the YAML or override values, rerun |
| `80` | Smoke | Required deployment object missing or seeded contract mismatch | Review the failing smoke row, fix the specific dependency, rerun |
| `90` | Seed | Fixture creation or downstream seeded check failed | Run cleanup if needed, fix the path-specific issue, rerun seeded deploy |
| `100` | Teardown | PAC delete gap or manual follow-up still needed | Review the teardown summary, complete manual items, rerun teardown if needed |

### Common failure modes and what they usually mean

| Symptom | Likely cause | Fix |
|---|---|---|
| Sponsor card never arrives | Teams connection reference not bound, wrong sponsor UPN, or sponsor timeout path misconfigured | Rebind the Teams connection, verify `fsi_sponsorupn`, test the sponsor flow directly |
| Reviewer app opens a placeholder URL | `fsi_intake_reviewerappurl` was never hydrated with the real app link | Set the real URL or override environment variable, rerun deploy |
| Approved request has no Agent ID | Tenant feature gate, missing blueprint ID, or Graph permission issue | Recheck Stage 3 prerequisites and `AGENT_INTAKE_AGENT_BLUEPRINT_ID` |
| Cross-border case denies immediately | Country mismatch with no Privacy override or allow-listed pair | Review `data_residency`, confirm `fsi_privacyoverride`, resubmit or appeal |
| Full-path request stalls after quorum | `fsi_mrmhandoffstatus` is pending or failed | Check the MRM target and the Flow 7 handoff behavior |
| Drift handoff never appears | `fsi_status` never reached `LiveTracking`, or drift target not configured | Verify the registry handoff completed and `fsi_intake_driftdetectorenv` is correct |
| Teardown leaves artifacts | This is expected for shared labels, classic Power Pages pieces, or shared blueprints | Read the teardown summary and remove only what is safe to remove manually |

## 15. Where to file issues

For product or repository issues, open an issue in the public repo:

- https://github.com/judeper/FSI-AgentGov-Solutions/issues

When you file an issue, include:

- the branch or release tag you deployed
- the exact `deploy.ps1` command used
- the exit code
- the relevant stage-summary lines
- the structured log file if policy allows you to share it

For tenant-specific incidents, keep the public issue focused on reproducible product behavior and route customer-specific credentials, screenshots, or regulated data through your internal support channel, AI governance lead, or Power Platform support process.
