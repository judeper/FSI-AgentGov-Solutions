# Pilot deployment runbook - agent-intake v1.0.0-preview

**Audience:** Power Platform administrator + InfoSec lead at the pilot firm.
**Estimated effort:** 4-8 hours of admin time across 2 calendar weeks.
**Pre-requisite reading:** `README.md`, `research/04-api-verification-spike.md`, `research/04-open-questions-resolved.md`, and `docs/orchestrator-architecture.md`.

This preview covers the **Express**, **Standard**, and **Full** intake paths, including the reviewer-app foundations, policy hydration, seeded lab data, and the downstream MRM and drift handoff contracts used by the broader solution suite.

## Pre-flight checklist

| # | Item | Owner | Verify |
|---|---|---|---|
| 1 | Power Platform environment provisioned (Managed Environment recommended) | PP admin | PPAC dashboard shows env in correct region |
| 2 | Dataverse capacity available (~50 MB for preview pilot) | PP admin | PPAC > Capacity |
| 3 | Automation identity selected and granted Dataverse System Customizer + Power Platform Administrator as needed | InfoSec | Role assignment documented |
| 4 | Microsoft Entra Agent ID feature available; `AgentIdentity.CreateAsManager` or `AgentIdentity.Create.All` consented; blueprint ID recorded | InfoSec | Entra admin center / Graph readiness check |
| 5 | Microsoft Purview Records Management available | InfoSec | Microsoft 365 admin center |
| 6 | Teams connector enabled for adaptive cards | M365 admin | Teams card test succeeds |
| 7 | Power Pages site provisioned and bound to the same environment as Dataverse | PP admin | Site URL reachable |

## Stage 1 - Lab preparation and prerequisites

1. Clone the repo:
   ```pwsh
   git clone https://github.com/judeper/FSI-AgentGov-Solutions.git
   Set-Location .\FSI-AgentGov-Solutions\agent-intake
   ```
2. Install Python dependencies used by the automation scripts:
   ```pwsh
   pip install requests msal pyyaml azure-identity jsonschema
   ```
3. Confirm `pac`, `az`, and PowerShell 7 are installed and available in `PATH`.
4. Review `docs/flow-build-prerequisites.md` and decide which values you will inject through environment overrides before the first run of `deploy.ps1`.
5. If you are using managed identity or a legacy service principal path, set those credentials before Stage 2.

## Stage 2 - Automated deployment (~5 minutes)

```pwsh
cd agent-intake/scripts
pwsh ./deploy.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com
```

The orchestrator runs Stages 1-7 (schema, solution shell, identity and records, maker surface, reviewer app, policy hydration, smoke). Each stage logs its status; see `docs/orchestrator-architecture.md` for the exit-code matrix.

For your first deployment, also seed the test data:

```pwsh
pwsh ./deploy.ps1 -EnvironmentUrl https://<your-env>.crm.dynamics.com -SeedTestData
```

If a stage fails, fix the underlying issue and re-run the orchestrator - it is idempotent and will pick up from the current state.

### Stage 2 (manual fallback)

If the orchestrator cannot be used in your environment, the per-stage manual steps are documented in:

- Stage 1: `docs/dataverse-schema.md`
- Stage 2: `docs/flow-build-prerequisites.md`
- Stage 3: `docs/identity-records-automation.md`
- Stage 4: `docs/portal-configuration.md`
- Stage 5: `docs/reviewer-app-build.md`
- Stage 6: `docs/admin-onboarding-guide.md` (created by enablement-docs)

## Stage 3 - Complete any remaining maker-surface tasks

1. Review the Stage 4 output from `deploy.ps1`.
2. If the orchestrator printed `MANUAL STEP REQUIRED:` for Power Pages, finish the classic site, page binding, and pre-fill configuration in `docs/portal-configuration.md` and `docs/maker-form-progressive-disclosure.md`.
3. Publish the site and confirm the URL in `fsi_intake_makerportalurl` returns HTTP 200 or 302 for an authenticated maker.

## Stage 4 - Complete workflow wiring and customer policy overrides

1. Review `docs/flow-configuration.md` and build or reconcile any Power Automate flows that still require manual designer work.
2. Confirm the solution environment variables hydrated by `deploy.ps1` match the customer values you expect to use in the pilot.
3. Customize `templates/policy-lookup-tables.yaml` for firm-specific sponsor SLA, sample rate, retention class, data residency defaults, and any MRM or drift-routing overrides.
4. Re-run `deploy.ps1` after policy changes so the hydrated environment-variable values and smoke checks stay aligned.

## Stage 5 - Validation and seeded-path walkthroughs

1. Run the baseline smoke test when you want a read-only validation pass:
   ```pwsh
   pwsh .\scripts\smoke_test.ps1 -EnvironmentUrl https://<your-org>.crm.dynamics.com
   ```
2. Run the seeded path checks after `deploy.ps1 -SeedTestData` or after a standalone seed operation:
   ```pwsh
   pwsh .\scripts\smoke_test.ps1 `
     -EnvironmentUrl https://<your-org>.crm.dynamics.com `
     -IncludeSeededDataChecks `
     -PathScope All
   ```
3. Manual end-to-end test: submit one Express-path request, one Standard-path request, and one Full-path request as a test maker; verify the resulting sponsor, reviewer, decision-log, and downstream handoff evidence lines up with the seeded examples.

## Stage 6 - Drift and downstream operations

1. Review `docs/drift-detection-integration.md` and confirm peer solutions can read the intake request ID, declared audience, declared data sources, sponsor UPN, decision-pack hash, and `fsi_entraagentid` from the registry handoff or decision-pack JSON.
2. Review `docs/mrm-integration.md` if the pilot includes Tier-1 Full-path requests.
3. Decide whether the pilot should keep the default synthetic seeded Agent IDs or opt into live Agent ID minting for seeded data through `AGENT_INTAKE_LIVE_AGENT_ID`.

## Pilot scope and go-live gate

- **Pilot population:** <= 25 makers, single department, 30 calendar days.
- **Go-live gate:** >= 80% of Express-path requests complete sponsor approval within 7 calendar days, no false-positive default-denies, and no security findings on the approved pilot paths.
- **Stop conditions:** any sponsor attestation captured for an unintended audience, any default-deny override that should have been allowed, or any Agent ID or MRM handoff failure not caught by the smoke workflow.

## Rollback

If the pilot fails the go-live gate or a stop condition is hit:

1. Disable the Power Automate flows.
2. Hide the Power Pages page from authenticated users.
3. Preserve all Dataverse data. Decision-log entries are regulated records and should remain retained according to the customer records policy.
4. File a pilot-failure report in customer change management.
5. Notify the sponsor population that the intake portal is paused and route requests through the legacy process until the next release.

## Still out of scope for v1.0.0-preview

- Conversational intake via an M365 Copilot declarative agent
- Automated environment provisioning on approval
- Localization beyond en-US
