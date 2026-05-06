# Pilot deployment runbook — agent-intake v0.2.0-preview

**Audience:** Power Platform administrator + InfoSec lead at the pilot firm.
**Estimated effort:** 4–8 hours of admin time across 2 calendar weeks.
**Pre-requisite reading:** `README.md`, `research/04-api-verification-spike.md`, `research/04-open-questions-resolved.md`.

The preview ships only the **Express path** (Tier-3 / Zone-3 / no risk signals → sponsor approval). Team, enterprise, or trigger-hit requests are captured and routed to follow-up review.

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

## Stage 1 — Foundation

1. Clone repo:
   ```pwsh
   git clone https://github.com/judeper/FSI-AgentGov-Solutions.git
   Set-Location .\FSI-AgentGov-Solutions\agent-intake
   ```
2. Install Python dependencies:
   ```pwsh
   pip install requests msal pyyaml azure-identity
   ```
3. Deploy Dataverse schema (dry-run first):
   ```pwsh
   $env:INTAKE_ENVIRONMENT_URL = 'https://<your-org>.crm.dynamics.com'
   python scripts/create_fsi_intake_dataverse_schema.py --dry-run --auth-mode managed-identity
   python scripts/create_fsi_intake_dataverse_schema.py --auth-mode managed-identity
   ```
4. Regenerate schema docs:
   ```pwsh
   python scripts/create_fsi_intake_dataverse_schema.py --output-docs docs/dataverse-schema.md
   ```

## Stage 2 — Records and identity

5. Create repo-local output folder:
   ```pwsh
   New-Item -ItemType Directory -Force .\.agent-intake-smoke | Out-Null
   ```
6. Create or document the Purview retention label:
   ```pwsh
   python scripts/setup_purview_retention_label.py --output .\.agent-intake-smoke\label-spec.json
   ```
   Follow the printed Purview portal or Security & Compliance PowerShell steps. If delegated Graph beta access is approved, verify with:
   ```pwsh
   python scripts/autodetect_purview.py --label-name FSI-AgentIntake-7yr --token-source cli
   ```
7. Verify Microsoft Entra Agent ID readiness and dry-run the create payload:
   ```pwsh
   python scripts/setup_entra_agent_id.py --check-consent --token-source cli
   python scripts/setup_entra_agent_id.py `
     --intake-request-id 00000000-0000-0000-0000-000000000000 `
     --display-name "Smoke-Test-Agent" `
     --sponsor-upn admin@contoso.com `
     --blueprint-id <agentIdentityBlueprintId> `
     --output .\.agent-intake-smoke\agentid-dryrun.json --dry-run
   ```

## Stage 3 — Maker surface

8. Build the Power Pages page following `docs/portal-configuration.md`; bind it to `fsi_intakerequest`.
9. Configure Graph pre-fill for `/me` and `/me/manager` or a pre-submit cloud flow.
10. Publish the site and confirm `https://<portal>.powerpages.microsoft.com/agent-intake` returns HTTP 200 for an authenticated maker.

## Stage 4 — Workflow

11. Build the three Power Automate flows following `docs/flow-configuration.md`:
    - `fsi-intake-router`
    - `fsi-intake-sponsor-card`
    - `fsi-intake-handoff`
12. Configure environment variables listed in `docs/flow-configuration.md`.
13. Customize `templates/policy-lookup-tables.yaml` for firm-specific sponsor SLA, sample rate, retention class, and data-residency defaults.

## Stage 5 — Smoke test

14. Run the smoke test:
    ```pwsh
    pwsh .\scripts\smoke_test.ps1 `
      -EnvironmentUrl https://<your-org>.crm.dynamics.com `
      -PortalUrl https://<portal>.powerpages.microsoft.com `
      -TokenSource cli
    ```
15. Manual end-to-end test: submit an Express-path request as a test maker; approve as sponsor; verify Agent ID handoff and registry shell row.

## Stage 6 — Drift wiring

16. Review `docs/drift-detection-integration.md` and confirm peer solutions can read the intake request ID, declared audience, declared data sources, sponsor UPN, and `fsi_entraagentid` from the registry handoff or decision-pack JSON.

## Pilot scope and go-live gate

- **Pilot population:** ≤ 25 makers, single department, 30 calendar days.
- **Go-live gate:** ≥ 80% of Express-path requests complete sponsor approval within 7 calendar days, no false-positive default-denies, no security findings on the auto-approval path.
- **Stop conditions:** any sponsor attestation captured for an unintended audience, any default-deny override that should have been allowed, any Agent ID creation failure not caught by smoke test.

## Rollback

If pilot fails the go-live gate or a stop condition is hit:

1. Disable the three Power Automate flows.
2. Hide the Power Pages page from authenticated users.
3. Preserve all Dataverse data. Decision-log entries are regulated records and must be retained according to customer records policy.
4. File a pilot-failure report in customer change management.
5. Notify sponsor population that the intake portal is paused and route requests through the legacy process until the next release.

## Out of scope for v0.2.0-preview

- Standard / Full review paths
- Reviewer queue Power App for InfoSec / Privacy / Compliance / MRM
- Conversational intake via M365 Copilot declarative agent
- Automated environment provisioning on approval
- Localization beyond en-US
