# Pilot deployment runbook — agent-intake v0.1.0-preview

**Audience:** Power Platform administrator + InfoSec lead at the pilot firm.
**Estimated effort:** 4–8 hours of admin time across 2 calendar weeks.
**Pre-requisite reading:** `README.md`, `research/04-api-verification-spike.md`, `research/04-open-questions-resolved.md`.

This runbook is the **only step-by-step deployment guide** for v0.1.0-preview. The MVP intentionally ships only the **Express path** (Tier-3 / Zone-3 / no risk signals → sponsor 1-click → auto-approve). Standard and Full paths are deferred to v0.2.0 and v0.3.0.

## Pre-flight checklist

| # | Item | Owner | Verify |
|---|---|---|---|
| 1 | Power Platform environment provisioned (Managed Environment recommended) | PP admin | PPAC dashboard shows env in correct region |
| 2 | Dataverse capacity available (~50 MB for v0.1.0-preview) | PP admin | PPAC > Capacity |
| 3 | Service principal created with Dataverse System Customizer + Power Platform Administrator + Microsoft Graph app permissions (`User.Read.All`, `RecordsManagement.Read.All`, `AgentIdentity.ReadWrite.All`) | InfoSec | Admin consent granted in Entra |
| 4 | Microsoft Entra Agent ID licensing enabled on tenant (GA May 1, 2026) | InfoSec | Verify via Entra portal |
| 5 | Microsoft Purview Records Management E5 license available | InfoSec | Microsoft 365 admin centre |
| 6 | Teams app catalog allows custom adaptive cards | M365 admin | Teams admin centre |
| 7 | Power Pages site provisioned and bound to the same env as Dataverse | PP admin | Portal URL reachable |

## Stage 1 — Foundation (~60 min)

1. **Clone repo** to admin workstation:
   ```pwsh
   git clone https://github.com/judeper/FSI-AgentGov-Solutions.git
   cd FSI-AgentGov-Solutions/agent-intake
   ```
2. **Install Python deps**:
   ```pwsh
   pip install -r ../scripts/shared/requirements.txt   # if file exists; else: requests, msal, pyyaml, azure-identity
   ```
3. **Deploy Dataverse schema** (dry-run first):
   ```pwsh
   $env:DATAVERSE_ENV_URL = 'https://<your-org>.crm.dynamics.com'
   python scripts/create_fsi_intake_dataverse_schema.py --dry-run
   # Review planned changes
   python scripts/create_fsi_intake_dataverse_schema.py
   ```
4. **Regenerate schema docs** (sanity check):
   ```pwsh
   python scripts/create_fsi_intake_dataverse_schema.py --output-docs docs/dataverse-schema.md
   ```

## Stage 2 — Records & identity (~45 min)

5. **Create Purview retention label**:
   ```pwsh
   python scripts/setup_purview_retention_label.py --output ./out/label-spec.json
   ```
   Follow the printed manual steps in the Purview portal. Verify with:
   ```pwsh
   python scripts/autodetect_purview.py --token-source cli
   ```
6. **Verify Entra Agent ID minting** (dry-run):
   ```pwsh
   python scripts/setup_entra_agent_id.py \
     --intake-request-id 00000000-0000-0000-0000-000000000000 \
     --display-name "Smoke-Test-Agent" \
     --owner-upn admin@contoso.com \
     --output ./out/agentid-dryrun.json --dry-run
   ```

## Stage 3 — Maker surface (~90 min)

7. **Build the Power Pages page** following `docs/portal-configuration.md`. Bind to `fsi_intakerequest`.
8. **Configure Microsoft Graph pre-fill** in Power Pages Liquid (or pre-handler flow).
9. **Publish** the portal and confirm `https://<portal>/agent-intake` returns HTTP 200 for an authenticated maker.

## Stage 4 — Workflow (~120 min)

10. **Build the 3 Power Automate flows** following `docs/flow-configuration.md`:
    - `fsi-intake-router`
    - `fsi-intake-sponsor-card`
    - `fsi-intake-handoff`
11. **Configure environment variables** listed in flow-configuration.md.
12. **Customise** `templates/policy-lookup-tables.yaml` for your firm (sponsor SLA, sample rate, retention class) and re-deploy if needed.

## Stage 5 — Smoke test (~30 min)

13. **Run the smoke test**:
    ```pwsh
    pwsh ./scripts/smoke_test.ps1 \
      -EnvironmentUrl https://<your-org>.crm.dynamics.com \
      -PortalUrl https://<portal>.powerappsportals.com \
      -TokenSource cli
    ```
14. **Manual end-to-end test**: submit an Express-path request as a test maker; approve as sponsor; verify Entra Agent ID minted and registry shell row created.

## Stage 6 — Drift wiring (~60 min)

15. Review `docs/drift-detection-integration.md` and confirm the four peer solutions (`unrestricted-agent-sharing-detector`, `scope-drift-monitor`, `agent-access-monitor`, `agent-365-lifecycle-governance`) are deployed and stamping `fsi_originintake_id` on their finding records.

## Pilot scope and go-live gate

- **Pilot population:** ≤ 25 makers, single department, 30 calendar days.
- **Go-live gate:** ≥ 80 % of Express-path requests auto-approve within 7 calendar days, no false-positive default-denies, no security findings on the auto-approval path.
- **Stop conditions:** any sponsor attestation captured for an unintended audience, any default-deny override that should have been allowed, any Entra Agent ID minting failure not caught by smoke test.

## Rollback

If pilot fails the go-live gate or a stop condition is hit:

1. **Disable the 3 Power Automate flows** (Power Automate portal → Turn off).
2. **Hide the Power Pages page** from authenticated users (web role removal).
3. **Preserve all Dataverse data** — do NOT drop tables. The decision-log entries are FINRA 4511 / SEC 17a-4 records and must be retained 7 years even from a failed pilot.
4. **File a pilot-failure report** in `agent-intake/research/05-pilot-results.md` (create if needed) documenting findings and root cause.
5. **Notify** sponsor population that the intake portal is paused and route requests through the legacy process (manual ServiceNow / SharePoint form / email) until v0.2.0.

## Out of scope for v0.1.0-preview

- Standard / Full review paths
- Reviewer queue Power App for InfoSec / Privacy / Compliance / MRM
- Conversational intake via M365 Copilot declarative agent
- Automated environment provisioning on approval (handed off to `environment-lifecycle-management`)
- Localization beyond en-US
- Mobile-app intake (browser-mobile only)
