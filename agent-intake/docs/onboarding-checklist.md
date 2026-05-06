# Customer Onboarding Checklist — Agent Intake v0.2.0-preview

A single-file checklist for customer admins deploying Agent Intake into a pilot tenant. Pair this with [`pilot-deployment-runbook.md`](pilot-deployment-runbook.md) for detailed steps.

> **Status note:** This is a **preview** release. Do not deploy broadly until pilot-firm walkthrough and your firm's AI Governance Committee + InfoSec + Compliance + Legal + IT review have signed off.

## Stage 0 — Prerequisites

### Licensing and tenant

- [ ] Microsoft 365 E3 or E5 with Power Platform licensing for makers
- [ ] Power Pages license for the portal
- [ ] Microsoft Entra Agent ID available in the target tenant/cloud
- [ ] Microsoft Purview Records Management enabled for retention labels
- [ ] Microsoft Teams enabled for sponsor adaptive cards

### Identities and permissions

- [ ] Power Platform Admin account available
- [ ] Microsoft 365 Records Management Admin account available (one-time retention label setup)
- [ ] Microsoft Entra Agent ID Administrator, Cloud Application Administrator, or Global Administrator available for Agent ID setup/consent
- [ ] Automation identity selected (managed identity/workload identity for automation; interactive admin accepted for pilot setup)
- [ ] Microsoft Graph permissions reviewed:
  - [ ] `User.Read` delegated for maker pre-fill; `User.Read.All` only if admin-scale lookup is needed
  - [ ] Delegated `RecordsManagement.Read.All` or `RecordsManagement.ReadWrite.All` for Graph beta retention-label verification/create, or manual Purview verification instead
  - [ ] `AgentIdentity.CreateAsManager` or `AgentIdentity.Create.All` for Agent ID creation
- [ ] Agent Identity blueprint created or identified; ID stored for `AGENT_INTAKE_AGENT_BLUEPRINT_ID`

### Repo and tooling

- [ ] Python 3.10+ installed
- [ ] PowerShell 7+ installed
- [ ] Python dependencies installed (`requests`, `msal`, `pyyaml`, `azure-identity` as needed)
- [ ] Repo cloned: `git clone https://github.com/judeper/FSI-AgentGov-Solutions.git`
- [ ] You can run `python agent-intake/scripts/seed_classification_rules.py --self-test` and see all PASS

### Governance sign-off

- [ ] Pilot scope agreed (department, makers, duration)
- [ ] Sponsor list identified
- [ ] InfoSec aware of 10% sample-audit cadence
- [ ] Compliance aware of FINRA 3110 attestation language in `templates/sponsor-approval-card.json`
- [ ] Legal/Records aware of FINRA 4511 / SEC 17a-4 / CFTC 1.31 retention assumptions
- [ ] Records Management aware of the `FSI-AgentIntake-7yr` Purview label

## Stage 1 — Customize policy defaults

- [ ] Review [`docs/decisions.md`](decisions.md)
- [ ] Update `templates/policy-lookup-tables.yaml` for sponsor SLA, sample rate, data residency, and retention labels
- [ ] Review `templates/sponsor-approval-card.json` attestation language with Counsel

## Stage 2 — Deploy schema and labels

- [ ] Dry-run: `python scripts/create_fsi_intake_dataverse_schema.py --dry-run --environment-url <pilot-env-url> --auth-mode managed-identity`
- [ ] Apply: `python scripts/create_fsi_intake_dataverse_schema.py --environment-url <pilot-env-url> --auth-mode managed-identity`
- [ ] Regenerate docs: `python scripts/create_fsi_intake_dataverse_schema.py --output-docs docs/dataverse-schema.md`
- [ ] Records Admin: run `python scripts/setup_purview_retention_label.py --output ./.agent-intake-smoke/label-spec.json`
- [ ] Create/verify `FSI-AgentIntake-7yr` in the Purview portal or via Security & Compliance PowerShell
- [ ] Verify label if delegated Graph beta access is approved: `python scripts/autodetect_purview.py --label-name FSI-AgentIntake-7yr --token-source cli`

## Stage 3 — Wire identities and consent

- [ ] Run `python scripts/setup_entra_agent_id.py --check-consent --token-source cli`
- [ ] Confirm `AgentIdentity.CreateAsManager` or `AgentIdentity.Create.All` is consented for the handoff identity
- [ ] Dry-run handoff with `--blueprint-id <agentIdentityBlueprintId>` before enabling Flow 3
- [ ] Verify environment list: `python scripts/autodetect_environments.py --output ./.agent-intake-smoke/environments.json --token-source cli`

## Stage 4 — Build maker surface

- [ ] Power Pages site provisioned
- [ ] Follow [`portal-configuration.md`](portal-configuration.md)
- [ ] Form binds to `fsi_intakerequest`
- [ ] Trigger questions T1–T6 use Yes / No / Not sure text values
- [ ] Sponsor field auto-populates from Graph `/me/manager` with override allowed
- [ ] Test as a non-admin user

## Stage 5 — Build workflow

Per [`flow-configuration.md`](flow-configuration.md). All flows are built manually in Power Automate designer.

- [ ] Flow 1 — classifier/router
- [ ] Flow 2 — Teams sponsor card using `Action.Submit`
- [ ] Flow 3 — handoff and decision evidence
- [ ] Connections and environment variables documented in customer-side ALM

## Stage 6 — Validate end-to-end

- [ ] Run `pwsh agent-intake/scripts/smoke_test.ps1`
- [ ] Submit a test intake as a known maker
- [ ] Verify auto-classification is Tier 3 / Zone 3 / Express
- [ ] Verify sponsor receives Teams card
- [ ] Sponsor approves
- [ ] Verify Microsoft Entra Agent ID service principal is created
- [ ] Verify entry created in `agent-registry-automation`
- [ ] Verify decision-log row has `FSI-AgentIntake-7yr` label evidence

## Stage 7 — Pilot kickoff

- [ ] Distribute [`maker-quick-start.md`](maker-quick-start.md)
- [ ] Distribute [`sponsor-cheat-sheet.md`](sponsor-cheat-sheet.md)
- [ ] Schedule 30-day InfoSec sample review
- [ ] Schedule 90-day value review with the AI Governance Committee
- [ ] Set up monitoring per [`drift-detection-integration.md`](drift-detection-integration.md)

## Stage 8 — Go / no-go decision

Before scaling beyond the pilot cohort, confirm:

- [ ] No undetected high-risk requests passed through Express
- [ ] Sponsors respond within SLA on average
- [ ] No regulatory or supervisory finding raised by Compliance against an approved agent
- [ ] Maker satisfaction informally positive
- [ ] AI Governance Committee approves the next cohort

## Rollback

- [ ] Disable the three Power Automate flows
- [ ] Disable or hide the Power Pages portal page
- [ ] Preserve existing Dataverse decision-log rows
- [ ] Document rollback in customer change management
