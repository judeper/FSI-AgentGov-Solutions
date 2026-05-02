# Customer Onboarding Checklist — Agent Intake v0.1.0-preview

A single-file checklist for customer admins deploying Agent Intake into a pilot tenant. Pair this with [`pilot-deployment-runbook.md`](pilot-deployment-runbook.md) for the detailed step-by-step.

> **Status note:** This is a **preview** release. Do not deploy to production until pilot-firm walkthrough and your firm's AI Governance Committee + InfoSec + Compliance + Legal + IT review have signed off.

---

## Stage 0 — Prerequisites (before you start)

### Licensing & tenant

- [ ] Microsoft 365 E3 or E5 with Power Platform per-app or per-user licensing for makers
- [ ] Power Pages license for the portal (1 production site)
- [ ] Microsoft Entra Agent ID feature available in your cloud (GA in commercial M365 from May 1, 2026; sovereign clouds per Microsoft roadmap)
- [ ] Microsoft Purview Records Management enabled for retention labels
- [ ] Microsoft Teams (for sponsor adaptive cards)

### Identities & permissions

- [ ] **Power Platform Admin** account available
- [ ] **Microsoft 365 Records Management Admin** account available (one-time, for retention label)
- [ ] **Microsoft Entra Global Admin or Application Administrator** account available (one-time, for app consent)
- [ ] Service principal created for the auto-detect scripts (or interactive admin run accepted)
- [ ] Microsoft Graph application permissions consented:
  - [ ] `User.Read.All`
  - [ ] `RecordsManagement.Read.All`
  - [ ] `AgentIdentity.ReadWrite.All`

### Repo + tooling on admin workstation

- [ ] Python 3.10+ installed
- [ ] PowerShell 7+ installed
- [ ] `pip install msal requests pyyaml` (or repo `requirements.txt`)
- [ ] Repo cloned: `git clone https://github.com/judeper/FSI-AgentGov-Solutions.git`
- [ ] You can run `python agent-intake/scripts/seed_classification_rules.py --self-test` and see 3/3 PASS

### Governance sign-off

- [ ] Pilot scope agreed (which department, how many makers, duration)
- [ ] Sponsor list identified (named line-of-business managers)
- [ ] InfoSec aware of 10% sample-audit cadence
- [ ] Compliance aware of FINRA 3110 attestation language in `templates/sponsor-approval-card.json`
- [ ] Legal aware of the FINRA 4511 / SEC 17a-4 / CFTC 1.31 7-year retention claim
- [ ] Records Management aware of the `FSI-AgentIntake-7yr` Purview label

---

## Stage 1 — Customize policy defaults (15 min)

- [ ] Copy `templates/policy-lookup-tables.yaml` to your customization folder
- [ ] Review every default in [`docs/decisions.md`](decisions.md) and override any that conflict with your firm's policy
- [ ] Common overrides:
  - [ ] `triggers.nydfs_enabled` → `true` if you are NY DFS regulated
  - [ ] `audit.sample_rate_express` → adjust from default `0.10` if InfoSec wants different
  - [ ] `auto_approve.additional_restrictions` → add `premium_connectors_disallowed` if your firm requires
  - [ ] `value_review.cadence_days` → adjust from default 90
- [ ] Edit `templates/sponsor-approval-card.json` → `attestation_text` if your Counsel requires different language

---

## Stage 2 — Deploy the schema and labels (30 min)

- [ ] Run dry-run first: `python scripts/create_fsi_intake_dataverse_schema.py --dry-run --environment-url <pilot-env-url>`
- [ ] Review the planned 9 tables and 7 option sets
- [ ] Apply: `python scripts/create_fsi_intake_dataverse_schema.py --interactive --environment-url <pilot-env-url>`
- [ ] Regenerate docs: `python scripts/create_fsi_intake_dataverse_schema.py --output-docs docs/dataverse-schema.md`
- [ ] Records Admin: run `python scripts/setup_purview_retention_label.py` to print the label spec, then create the `FSI-AgentIntake-7yr` label manually in the Purview portal (Graph does not yet support label creation)
- [ ] Verify label exists: `python scripts/autodetect_purview.py --check-label FSI-AgentIntake-7yr`

---

## Stage 3 — Wire up identities and consent (15 min)

- [ ] Run `python scripts/setup_entra_agent_id.py --check-consent` — should report all 3 Graph permissions consented
- [ ] If not consented, follow the printed admin-consent URL
- [ ] Verify maker auto-fill: `python scripts/autodetect_environments.py --user <pilot-maker-upn>` — should return manager + environment list

---

## Stage 4 — Build the maker surface (60–90 min)

- [ ] Power Pages site provisioned
- [ ] Follow [`portal-configuration.md`](portal-configuration.md) to build the 10-Q Express form
- [ ] Form binds to `fsi_intakerequest` table
- [ ] Trigger questions T1–T6 use the Yes/No/Not-sure option set
- [ ] Sponsor field auto-populates from Graph `/me/manager` (override allowed)
- [ ] Test as a non-admin user: submit a fully-No request and verify it lands in Dataverse

---

## Stage 5 — Build the workflow (60–90 min)

Per [`flow-configuration.md`](flow-configuration.md). All flows are built manually in Power Automate designer (the repo does not ship exported flow JSON).

- [ ] **Flow 1 — Classifier** — runs `seed_classification_rules.py` logic on submit, sets `fsi_pathused`
- [ ] **Flow 2 — Sponsor card** — sends Teams adaptive card from `templates/sponsor-approval-card.json` with FINRA 3110 attestation
- [ ] **Flow 3 — Handoff** — on approve, calls `setup_entra_agent_id.py` to mint Agent ID and writes to `agent-registry-automation`
- [ ] Flow 1 + 2 + 3 share a single connection reference; document in your customer-side ALM

---

## Stage 6 — Validate end-to-end (30 min)

- [ ] Run `pwsh agent-intake/scripts/smoke_test.ps1` — all 7 read-only checks pass
- [ ] Submit a test intake as a known maker
- [ ] Verify auto-classification is correct (Tier 3 / Zone 3 / Express)
- [ ] Verify sponsor receives Teams card
- [ ] Sponsor approves
- [ ] Verify Entra Agent ID is minted (check Entra portal)
- [ ] Verify entry created in `agent-registry-automation` Dataverse table
- [ ] Verify maker receives notification with Agent ID
- [ ] Verify decision-log row in `fsi_intakedecisionlog` has `FSI-AgentIntake-7yr` label applied

---

## Stage 7 — Pilot kickoff (1 day)

- [ ] Distribute [`maker-quick-start.md`](maker-quick-start.md) to the pilot maker cohort
- [ ] Distribute [`sponsor-cheat-sheet.md`](sponsor-cheat-sheet.md) to the named sponsors
- [ ] Schedule 30-day check-in with InfoSec to review the 10% sample
- [ ] Schedule 90-day value review with the AI Governance Committee
- [ ] Set up monitoring per [`drift-detection-integration.md`](drift-detection-integration.md)

---

## Stage 8 — Go / no-go decision (after pilot)

Before scaling beyond the pilot cohort, confirm:

- [ ] No undetected high-risk requests passed through Express (review the 10% sample)
- [ ] Sponsors are clicking within SLA on average
- [ ] No regulatory or supervisory finding raised by Compliance against any approved agent
- [ ] Maker satisfaction informally positive
- [ ] AI Governance Committee approves general availability for the next cohort

---

## Rollback

If any stage fails or you need to back out:

- [ ] Disable the 3 Power Automate flows (turns off intake processing)
- [ ] Disable the Power Pages portal (blocks new submissions)
- [ ] Existing decision-log rows remain — they are immutable and required for the regulatory record
- [ ] Document the rollback decision in your firm's change-management system
- [ ] See [`pilot-deployment-runbook.md`](pilot-deployment-runbook.md) Stage 6 for the full rollback procedure
