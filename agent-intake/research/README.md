# `agent-intake` — Phase A + Phase B-prep research artifacts

**Status:** Research and design only. **No solution scaffold has been built.** This folder exists to preserve the research record on the `feat/agent-intake-research` branch.

The proposed `agent-intake` solution would help Financial Services organizations operate a productive intake process for users requesting new AI agents (Copilot Studio, Agent Builder, declarative agents, custom-engine agents, Azure AI Foundry agents). The intake supports compliance with FINRA 3110/4511/25-07, SEC 17a-4(f), CFTC 1.31, GLBA 501(b), SOX 302/404, and firm-policy MRM aligned to OCC 2026-13 + SR 11-7.

## Artifacts

| # | File | Description |
|---|---|---|
| 01a | `01-phase-a-report-gpt.md` | GPT-5.4 research report on prior art (Microsoft CoE Kit, Copilot Studio Kit, vendor offerings, ServiceNow / Salesforce competitive patterns) |
| 01b | `01-phase-a-report-claude.md` | Claude Sonnet 4.6 Thinking research report on the same scope |
| 01c | `01-phase-a-fit-assessment.md` | User-led synthesis of the two reports + counter-research (OCC 2026-13 gen-AI exclusion, Entra Agent ID GA May 1 2026) + 7 locked product-owner decisions |
| 02a | `02-question-catalog-research-prompt.md` | Research prompt drafted to elicit the question catalog needed to drive 12 admin decisions at intake |
| 02b | `02-question-catalog-report-claude.md` | Claude's 137-question catalog response across 12 categories with auto-detect playbook, disqualifier rules, anti-patterns, and bibliography |
| 02c | `02-question-catalog-evaluation.md` | Standalone evaluation of the catalog: A-J scorecard, 5 quality fixes, 8 missing questions, 3 API endpoints to verify, counter-research items |
| 03 | `03-intake-form-design-v1.md` | **Primary deliverable.** Risk-tiered progressive form architecture (Express 10 Q / Standard 20 Q / Full 35 Q) with auto-classification rules, policy lookup tables, adoption metrics, and 10 open stakeholder questions |

## Locked product-owner decisions (carry into Phase B)

1. **Auto-approve** for Tier-3 + Zone-3 + no-risk-signal + sponsor sign-off + passive InfoSec sample-log *(Note: zone-numbering convention reconciled in 03 §0 — Zone-1 = Enterprise, Zone-3 = Personal)*
2. **Standalone solution** (no CoE Innovation Backlog dependency)
3. **Maker UX build order:** Power Pages portal → M365 Copilot declarative agent → Teams sponsor app
4. **MRM framing:** Tier-gated MRM as firm policy for ALL agent types
5. **Records retention:** 7 years (covers SEC 17a-4 / FINRA 4511 / CFTC 1.31)
6. **All five agent types in scope:** Copilot Studio classic, Agent Builder, declarative, custom-engine, Azure AI Foundry
7. **Catalog placement:** v0.1.0-preview when scaffolded
8. **Auto-mint Entra Agent ID at handoff** (GA May 1, 2026)

## Phase B status: PAUSED

Phase B (form build + Dataverse schema + Power Pages portal + Teams sponsor card) is intentionally paused pending:

- Pilot-firm walkthrough of the 10 open stakeholder questions in `03-intake-form-design-v1.md` §12
- 30-minute API verification spike on the 3 ⚠️ endpoints flagged in `02-question-catalog-evaluation.md` §5 (Purview catalog API path, Power Platform DLP `/policies` endpoint shape, Graph beta retentionLabels path)
- AI Governance Committee + InfoSec + Compliance + Legal + IT-architecture review of the proposed design

## How to read this folder

If you have 5 minutes: read this README + skim §14 of `03-intake-form-design-v1.md` (the "by the numbers" summary).

If you have 30 minutes: read all of `03-intake-form-design-v1.md`.

If you want the full provenance: read in numeric order (01 → 02 → 03).

## Notes for future contributors

- This folder is a **research record**, not a solution. Do not promote any of these documents to `site-docs/` or `manifest.yaml` until Phase B scaffolding begins.
- The 137-question Claude catalog is preserved verbatim as a back-office field dictionary. Most of those questions are computed or auto-detected, not asked of makers — see `03-intake-form-design-v1.md` §6-8 for the mapping.
- Do not check this branch into `main` until Phase B is approved to start. The branch may be force-updated as design iterates.
