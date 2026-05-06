# `agent-intake` — Phase A + Phase B-prep research artifacts

**Status:** Phase A research + Phase B MVP scaffold COMPLETE on this branch (`feat/agent-intake-research`). The solution at `../` is wired and self-deployable per `../docs/pilot-deployment-runbook.md`. **Held as draft PR** pending pilot-firm walkthrough — see "Phase B status" below.

The proposed `agent-intake` solution would help Financial Services organizations operate a productive intake process for users requesting new AI agents (Copilot Studio, Agent Builder, declarative agents, custom-engine agents, Azure AI Foundry agents). The intake supports compliance with FINRA 3110/4511/25-07, SEC 17a-4(f), CFTC 1.31, GLBA 501(b), SOX 302/404, and firm-policy MRM aligned to OCC 2026-13 + SR 11-7.

## Artifacts

| # | File | Description |
|---|---|---|
| 01a | `01-phase-a-report-gpt.md` | GPT-5.4 research report on prior art (Microsoft CoE Kit, Copilot Studio Kit, vendor offerings, ServiceNow / Salesforce competitive patterns) |
| 01b | `01-phase-a-report-claude.md` | Claude Sonnet 4.6 Thinking research report on the same scope |
| 01c | `01-phase-a-fit-assessment.md` | User-led synthesis of the two reports + counter-research (OCC 2026-13 gen-AI exclusion, Entra Agent ID feature availability should be verified in the target tenant/cloud) + 7 locked product-owner decisions |
| 02a | `02-question-catalog-research-prompt.md` | Research prompt drafted to elicit the question catalog needed to drive 12 admin decisions at intake |
| 02b | `02-question-catalog-report-claude.md` | Claude's 137-question catalog response across 12 categories with auto-detect playbook, disqualifier rules, anti-patterns, and bibliography |
| 02c | `02-question-catalog-evaluation.md` | Standalone evaluation of the catalog: A-J scorecard, 5 quality fixes, 8 missing questions, 3 API endpoints to verify, counter-research items |
| 03 | `03-intake-form-design-v1.md` | **Primary deliverable.** Risk-tiered progressive form architecture (Express 10 Q / Standard 20 Q / Full 35 Q) with auto-classification rules, policy lookup tables, adoption metrics, and 10 open stakeholder questions |
| 04a | `04-api-verification-spike.md` | API verification spike: PPAC env + DLP endpoints verified; Graph retention label reads need delegated `RecordsManagement.Read.All`; Purview catalog deferred to pilot |
| 04b | `04-open-questions-resolved.md` | PO defaults for OQ-A through OQ-J + 7 stakeholder questions, all configurable via `../templates/policy-lookup-tables.yaml` |

## Locked product-owner decisions (carry into Phase B)

1. **Auto-approve** for Tier-3 + Zone-3 + no-risk-signal + sponsor sign-off + passive InfoSec sample-log *(Note: zone-numbering convention reconciled in 03 §0 — Zone-1 = Enterprise, Zone-3 = Personal)*
2. **Standalone solution** (no CoE Innovation Backlog dependency)
3. **Maker UX build order:** Power Pages portal → M365 Copilot declarative agent → Teams sponsor app
4. **MRM framing:** Tier-gated MRM as firm policy for ALL agent types
5. **Records retention:** 7 years (covers SEC 17a-4 / FINRA 4511 / CFTC 1.31)
6. **All five agent types in scope:** Copilot Studio classic, Agent Builder, declarative, custom-engine, Azure AI Foundry
7. **Catalog placement:** v0.1.0-preview when scaffolded
8. **Auto-mint Entra Agent ID at handoff** (feature availability should be verified in the target tenant/cloud)

## Phase B status: COMPLETE — held as draft PR

Phase B (Dataverse schema + portal spec + flow build docs + classification engine + auto-detect + handoff scripts + smoke test + pilot runbook) is COMPLETE in `../scripts/`, `../docs/`, and `../templates/`. The MVP ships only the **Express path** (Tier-3 + Zone-3 + no-risk-signal + sponsor 1-click → auto-approve). Standard / Full deferred to v0.2.0+.

## Phase D status: COMPLETE — adoption polish shipped

Pre-pilot polish artifacts shipped to drive maker + sponsor + admin adoption:

- `../docs/maker-quick-start.md` — 1-page maker guide
- `../docs/sponsor-cheat-sheet.md` — 1-page sponsor guide with FINRA 3110 attestation walkthrough
- `../docs/onboarding-checklist.md` — single-file customer admin checklist (Stage 0–8 + rollback)
- `../docs/decisions.md` — Architecture Decision Record consolidating the 10 PO-locked decisions in `04-open-questions-resolved.md`
- Mermaid architecture diagram in `../README.md`

**Held as draft PR pending:**

- Pilot-firm walkthrough of the open stakeholder questions captured in `04-open-questions-resolved.md` (resolved with PO defaults that customers can override via `../templates/policy-lookup-tables.yaml`)
- Customer admin grants of 3 Microsoft Graph app permissions documented in `04-api-verification-spike.md`
- AI Governance Committee + InfoSec + Compliance + Legal + IT-architecture review of the shipped artifacts

## How to read this folder

If you have 5 minutes: read this README + skim §14 of `03-intake-form-design-v1.md` (the "by the numbers" summary).

If you have 30 minutes: read all of `03-intake-form-design-v1.md`.

If you want the full provenance: read in numeric order (01 → 02 → 03).

## Notes for future contributors

- This folder is a **research record**, preserved alongside the live solution at `../`. Do NOT promote these documents to `site-docs/` or `manifest.yaml`. They are excluded from CI language checks and from the published MkDocs nav.
- The 137-question Claude catalog is preserved verbatim as a back-office field dictionary. Most of those questions are computed or auto-detected, not asked of makers — see `03-intake-form-design-v1.md` §6-8 for the mapping, and `../docs/auto-detect-playbook.md` for the implemented auto-detect map.
- The branch is held as a **draft PR**. Do not merge to `main` until pilot-firm input is received (per locked decision).
