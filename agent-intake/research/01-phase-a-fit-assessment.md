# Fit Assessment — `agent-intake` Solution Research

**Date:** 2026-04-30  •  **Branch:** `feat/agent-intake-research`  •  **Status:** Phase A complete, awaiting decisions

---

## 0. Reading list

| # | Source | Origin | Saved at |
|---|---|---|---|
| 1 | "Pre-Build AI Agent Intake in a Regulated FSI Environment: Build, Adopt, or Extend?" | Copilot Researcher (GPT-style) | `files/report-1.md` |
| 2 | "US FSI AI Agent Intake — Build, Adopt, or Extend Decision Brief" | Copilot Researcher (Claude-style) | `files/report-2.md` |
| 3 | "AI Agent Intake Governance — Research Synthesis" | User-prepared synthesis comparing 1 & 2 | `files/synthesis-user.md` |

> **Note:** Originally we expected 3 distinct research reports. In practice we received 2 research reports + 1 user-prepared synthesis. The synthesis is treated as a third input, not a research source.

---

## 1. Verdict per report

| | **Report 1 (GPT)** | **Report 2 (Claude)** |
|---|---|---|
| **Verdict** | Adoptable with modifications | **Adoptable as-is for Phase B planning** |
| **One-paragraph reasoning** | Solid landscape scan and a workable 5-stage model, but lighter on data model, weaker decision matrix (no numeric scoring), no immutable-decision-record design pattern, and no explicit OCC 2026-13 callout. Strongest unique contribution: Google Agentspace / ServiceNow AI Agent Studio competitive patterns. | More rigorous: 7-stage canonical model with cross-cutting retention/telemetry bands, complete 9-entity Dataverse data model with `fsi_` prefix, weighted decision matrix (Option B = 86/100), 8-epic backlog sized for 4-6 FTE / 8-12 weeks, explicit OCC 2026-13 update, explicit Entra Agent ID preview risk callout. Strongest unique contribution: ServiceNow AI Control Tower MCP-server approval workflow + AvePoint AgentPulse Command Center analysis. |

**Both reports agree on the recommendation: Option B — Extend the CoE Starter Kit Innovation Backlog with FSI overlays on Dataverse.** This converges with our own pre-research instinct.

---

## 2. Scorecard (criteria A–H, 1-5 scale)

| Criterion | R1 (GPT) | R2 (Claude) | Synthesis |
|---|---|---|---|
| **A. IT-admin decision coverage (the seven sub-questions)** | 3 | **5** | R2 covers all 7 explicitly; R1 covers 4 |
| **B. FSI regulatory fit (specific rules cited)** | 3 | **5** | R2 cites FINRA 3110/4511/24-09/25-07, SEC 17a-4, SR 11-7, **OCC 2026-13**, CFTC 1.31, GLBA 501(b), SOX 302/404 with traceability per backlog item |
| **C. Microsoft platform realism (GA vs preview)** | 3 | **5** | R2 explicitly flags 9 components by maturity; R1 conflates some |
| **D. Integration with our 35-solution suite** | 2 | **4** | R2 names handoff to existing registry / lifecycle solution explicitly |
| **E. Build-vs-adopt clarity** | 3 | **5** | R2 has weighted matrix with second-best option named (D); R1 is qualitative |
| **F. Implementation realism** | 2 | **5** | R2 has 8 epics × 30+ stories with dependencies, FTE sizing, DoD hints |
| **G. Source quality (primary, recent, no inventions)** | 3 | **4** | Both cite primary sources; R2 is more disciplined about preview/GA distinction |
| **H. Maker UX (the 8 sub-questions)** | 3 | **4** | R2 names Power Pages + Teams + M365 Copilot declarative agent + Outlook fallback; R1 lighter on UX |
| **Total / 40** | **22** | **37** | |

**Weighted impression:** Report 2 is the stronger working draft; Report 1 contributes complementary breadth (vendor landscape, competitive patterns).

---

## 3. Gap analysis — what our current plan was missing

Items present in at least one report but absent from our pre-research plan, categorized:

| Gap | Source | Category | Why it matters |
|---|---|---|---|
| **Stage 0 "Discover & educate"** as a first-class stage | R2 | **Must-add** | Without it, makers route around intake; FINRA 3110 supervision presupposes a known channel |
| **Auto-classify / triage stage with AI Builder** as a separate stage between capture and human review | R2 | **Must-add** | Reduces admin time-to-decide; surfaces duplicates; pre-fills tier/zone |
| **Cross-cutting "retention & audit log" band** spanning every stage (vs. only Stage 6) | R2 | **Must-add** | Each state change becomes a regulated artifact; matches SEC 17a-4 expectations |
| **Immutable decision-log table with hash chain + nightly export to immutable blob storage** | R2 | **Must-add** | Defensible second copy independent of Dataverse; passes SEC 17a-4(f) attempt-to-delete tests |
| **9-entity Dataverse data model** with explicit FK back to existing `Innovation Backlog Idea` | R2 | **Must-add** | Backwards compatibility preserves voting/idea history |
| **Tier-gated MRM routing** (Tier 1/2 → MRM queue, Tier 3 auto-bypass with rationale) | R2 | **Must-add** (with caveat — see Section 6) | Avoids overburdening MRM team for low-risk Agent Builder requests |
| **Sponsor signature payload with Entra OID + timestamp + payload hash** | R2 | **Must-add** | FINRA 3110 supervision evidence |
| **Restricted-data signal capture: NPI / MNPI / PCI / PHI** as explicit categories (not generic "PII") | R2 | **Must-add** | GLBA 501(b), Reg FD, MNPI handling |
| **Cross-border data signal** as a discrete field | R2 | **Must-add** | Data residency / GDPR / PIPL exposure |
| **Conflict-of-interest signal** as a discrete field | R2 | **Must-add** | FINRA 3110 supervision pattern |
| **"Suitability advice" / "trade decision" / "credit decision"** as autonomy-level enumerations | R2 | **Should-add** | Pre-flags FINRA 25-07 suitability concerns and credit-decision oversight |
| **Power Pages + Teams + M365 Copilot declarative agent + Outlook fallback** as multi-surface UX | R2 | **Should-add** | Our plan only had the Copilot Studio agent UX; multi-surface is more robust |
| **Email-to-intake fallback flow** | R2 | **Nice-to-add** | Marketed as low-fidelity; useful for legacy makers |
| **AI Builder classifier on intake itself** for risk-signal extraction | R2 | **Should-add** | Productivity driver: removes manual tagging |
| **Duplicate detection via semantic similarity + name/owner heuristics** | R2 | **Should-add** | Productivity driver: avoids wasted admin time |
| **Reviewer scorecard (SLA per role, backlog aging)** | R2 | **Should-add** | Productivity driver: surfaces stuck approvals |
| **Quarterly attestation report (auto-generated SOX-style)** | R2 | **Should-add** | SOX 302/404 evidence, reduces audit prep time |
| **ServiceNow change-record mirror** for firms using SN as system of record | R2 | **Nice-to-add** | Optional integration if firm uses SN |
| **Agent registry hand-off as typed payload** (request id, tier, zone, sponsor OID, conditions, audit pointer) | R2 | **Must-add** | Clean contract with our existing `agent-registry-automation` solution |
| **`microsoft/Microsoft-AI-Decision-Framework`** GitHub repo as upstream embedded in Stage 2 | R2 | **Should-add** | Helps maker pick agent type before submission |
| **DSPM-for-AI** signal lookup in Purview during triage | R2 | **Should-add** | Surfaces sensitivity signals automatically |
| **`agent-governance-toolkit` (microsoft/agent-governance-toolkit)** as runtime governance complement | R2 | **N/A — out of scope** | Runtime, not pre-build |
| **Google Agentspace "Agent Gallery"** maker-facing discovery pattern | R1 | **Should-add** | Productivity driver: makes existing approved agents reusable, suppresses duplicate intake |
| **Salesforce Einstein Trust Layer** as a runtime concept | R1 | **N/A — out of scope** | Runtime, not pre-build |
| **ServiceNow AI Agent Studio** integration with standard change-management | R1 | **Nice-to-add** | Optional handoff if firm uses SN |
| **Maker feedback survey + appeal path** | R2 | **Must-add** | UX requirement we already had; R2 confirms with concrete Epic 7.2 |
| **OCC Bulletin 2026-13 update** (rescinds OCC 2011-12 from April 17, 2026) | R2 (verified) | **Critical update** | All our solution READMEs / playbooks that cite OCC 2011-12 need rewording. **R2 missed that 2026-13 explicitly excludes generative & agentic AI from MRM scope** — see Section 6. |

---

## 4. Feature borrow-list (what to steal from each report)

### From Report 1 (GPT)
| Feature | Productivity impact | Cost | Dependency |
|---|---|---|---|
| Google Agentspace-style "Agent Gallery" pattern in the discover stage | High — suppresses duplicate intake by surfacing existing approved agents | Low (read-only view over PPAC Agent Inventory) | PPAC Agent Inventory access |
| ServiceNow AI Agent Studio change-management integration pattern | Medium — only if firm uses SN | Medium (REST integration) | ServiceNow SKU |
| Salesforce Trust Layer concept reframed as runtime guardrails | Medium — informs handoff payload to runtime solutions | Low (design pattern only) | None |

### From Report 2 (Claude)
| Feature | Productivity impact | Cost | Dependency |
|---|---|---|---|
| 7-stage canonical model with cross-cutting retention band | High — establishes the spine | Low (design pattern) | None |
| 9-entity Dataverse data model with FK to existing Innovation Backlog | High — schema clarity unblocks all later work | Low-medium (schema design) | CoE Innovation Backlog installed |
| Auto-classify stage with AI Builder | High — cuts admin time-to-decide significantly | Medium (AI Builder model + training corpus) | AI Builder licenses |
| Hash-chained immutable decision log + nightly export to immutable blob | High — defensible records story | Medium (Azure Storage + DR test) | Azure subscription |
| Tier-gated MRM routing (Tier 3 auto-bypass) | High — prevents MRM team overload | Low (workflow logic) | Firm MRM API |
| Multi-surface UX (Power Pages + Teams + M365 Copilot agent + Outlook) | High — meets makers where they are | Medium-high (4 surfaces to build) | M365 Copilot / Power Pages SKUs |
| Sponsor signature with Entra OID + timestamp + hash | High — FINRA 3110 evidence | Low | Entra ID |
| Reviewer SLA scorecard | Medium — surfaces stuck approvals | Low (Power BI) | Power BI workspace |
| Quarterly attestation report | High — turns intake into ongoing SOX evidence | Medium (report design) | Power BI |
| Microsoft-AI-Decision-Framework embedded in Stage 2 | Medium — helps maker pre-classify agent type | Low (link + summary) | None |
| DSPM-for-AI signal lookup during triage | Medium — auto-surfaces sensitivity | Medium (Purview API) | Purview |
| Auto-approve where policy permits (Tier-3 + Zone-1 + no risk signals) | **Very high** — most Agent Builder requests can flow through in minutes | Low (rule logic on top of existing flows) | Tier/zone classifier |

### From the User Synthesis (already done, validated)
| Insight | Use |
|---|---|
| Both reports converge on Option B | Confidence boost — proceed with extend pattern |
| Claude is more conservative on vendor (56) than GPT (64) | Adopt the more conservative posture for Phase B planning |
| Claude flagged Entra Agent ID Preview risk; counter-research now confirms **GA May 1, 2026** | Update plan: design assumes GA, not preview (see Section 6) |

---

## 5. Productivity-driver inventory

Mapped to the five productivity goals from our plan:

### A. Reduce maker time-to-submit (target: 3-5 minutes)
- M365 profile pre-fill (department, manager, country) — borrowed from our plan
- Conversational M365 Copilot intake agent (eat our own dog food) — borrowed from R2
- Save-and-resume on Power Pages portal — our plan
- Microsoft-AI-Decision-Framework embedded link — borrowed from R2
- Plain-language progressive disclosure — our plan

### B. Reduce admin time-to-decide
- AI Builder auto-classification of agent type — borrowed from R2
- Auto-tier and auto-zone proposal — borrowed from R2
- Auto-DLP signal lookup via Purview — borrowed from R2
- Duplicate detection via semantic similarity — borrowed from R2
- Sponsor auto-lookup from Graph (manager, department) — our plan + R2 sponsor entity

### C. Reduce back-and-forth
- Validation at point of capture (required fields, format) — table-stakes
- "You might also mean…" duplicate detection — borrowed from R2
- Missing-info nudges before submit — our plan
- Agent Gallery view of existing approved agents — borrowed from R1

### D. Reduce approval cycle time
- Parallel reviews (InfoSec / Privacy / Compliance) where independent — borrowed from R2
- Tier-3 + Zone-1 + no-risk-signal **auto-approval** with sponsor sign-off — borrowed from R2 (highest leverage)
- Teams adaptive-card approvals (sponsor in their working surface) — borrowed from R2
- Reviewer SLA scorecard — borrowed from R2

### E. Reduce post-decision toil
- Auto-create handoff payload to existing `agent-registry-automation` — our plan + R2 contract
- Auto-provision target environment via Foundry / Copilot Studio API — borrowed from R2
- Auto-mint Entra Agent ID blueprint (assuming GA on May 1, 2026) — borrowed from R2 (now stronger)
- Auto-grant maker role on approval — borrowed from R2
- Quarterly auto-attestation pack — borrowed from R2

---

## 6. Counter-research findings (devil's advocate)

| Claim | Source | Verification | Verdict |
|---|---|---|---|
| **OCC Bulletin 2011-12 rescinded April 17, 2026, replaced by OCC 2026-13** | R2 | Verified via OCC, FDIC, Federal Reserve press releases (April 17, 2026) | **TRUE** — but R2 missed the critical detail below |
| **OCC 2026-13 covers generative & agentic AI for MRM tiering** | R2 (implied) | OCC 2026-13 **explicitly excludes** generative and agentic AI models from scope; institutions encouraged to set their own controls | **FALSE** — major caveat. SR 11-7-style Tier 1/2/3 routing for *generative* agents is now **firm-discretionary**, not regulator-mandated. We can still adopt the pattern, but we must not represent it as "required by SR 11-7 / OCC 2026-13" — it is internal policy. **All our solution READMEs need to be careful here.** |
| **SR 11-7 remains in force at the Federal Reserve** | R2 | Verified | **TRUE** — and unaffected by OCC 2026-13 because OCC 2026-13 is interagency but each agency issues separately |
| **Microsoft Entra Agent ID Governance is preview, GA timing uncertain** | R2 | **GA on May 1, 2026 with Agent 365** ($15/user/mo or M365 E7 at $99/user/mo). Today is April 30, 2026 | **STALE** — preview risk callout is now overstated. Design can assume GA. Story 6.4 dependency is no longer a risk. |
| **Power CAT Copilot Studio Kit Compliance Hub is post-creation only** | R2 | Verified via repo README — Compliance Hub evaluates *Agent Inventory* configurations, not pre-build requests | **TRUE** |
| **CoE Innovation Backlog is stale (last commit 3 yrs, doc 02/2022)** | R2 | Verified — Learn page is still live and current in URL but content is unchanged from 2022 | **TRUE** |
| **AvePoint AgentPulse Command Center GA March 9, 2026** | R2 | Plausible per AvePoint product page; not independently verified at vendor press release level | **PROBABLY TRUE** — flag for Q9 in Open Questions |
| **ServiceNow AI Control Tower MCP-server approval workflow exists** | R2 | Cited a ServiceNowDocs GitHub branch | **PROBABLY TRUE** — confirm before depending on it |
| **Microsoft has no published pre-build agent intake template** | Both reports | Confirmed — Innovation Backlog is for apps/flows, Compliance Hub is post-creation, CAF is guidance only, Maker Onboarding is adoption tooling | **TRUE** — this is the foundational "no off-the-shelf solution" finding that justifies the build |
| **DLP-at-intake feasibility (simulate Purview DLP against proposed connector set)** | Implied in both reports | DLP can be queried against connectors but no public API simulates "what-if" against a proposed-but-not-deployed connector set. Workaround: rule-based check against allowed-connector list per environment. | **PARTIALLY TRUE** — full DLP simulation is not GA; rule-based equivalent is feasible |
| **Conversational intake via M365 Copilot declarative agent feasibility** | R2 + our plan | Declarative agents are GA; can read/write Dataverse via custom connectors; can branch with Power Fx; **cannot natively run long-running approval flows** — must hand off to Power Automate. Hybrid is required. | **CONDITIONALLY TRUE** — the conversational front door is feasible, but the orchestration must live in Power Automate, not in the agent itself. Plan Power Pages + Power Automate as the spine, agent as the friendly wrapper. |

---

## 7. Synthesized "best-of" intake design (Phase B starting point)

### Spine
- **7-stage canonical model from R2** (Discover → Capture → Auto-classify → Tier/Zone → Multi-disciplinary review → Decision → Handoff) with cross-cutting **retention/audit band** and **telemetry band**

### Maker UX
- **Primary**: Power Pages portal (Entra-required, M365 profile pre-fill, save-and-resume, WCAG AA, mobile-friendly) — 3-5 minute target for simple Agent Builder requests
- **Secondary**: M365 Copilot **declarative** intake agent as conversational front door (writes to Dataverse via custom connector; hands off to the same Power Automate flows)
- **Tertiary**: Microsoft Teams app for sponsors / reviewers to approve in their working surface (Adaptive Cards)
- **Failover**: Outlook + Power Automate email-to-intake (low-fidelity)
- **Lifecycle visibility**: status notifications at every stage + self-service status check via the conversational agent
- **Constructive denial**: reason + suggested alternatives ("use existing agent X", "try Agent Builder instead", "narrow data sources to remove DLP conflict") + appeal path
- Borrowed from R1: an "Agent Gallery" pre-search view of existing approved agents to suppress duplicate intake

### Decision-support for IT admin (the 7 questions)
- **Agent type** — auto-suggest from form answers + Microsoft-AI-Decision-Framework lookup
- **Data sources / DLP impact** — auto-lookup against PPAC environment DLP allowed-connector list; rule-based equivalent of DLP simulation; flag conflicts
- **Environment placement** — rule-based (zone + sensitivity + tier) suggests "use existing X" or "provision new in zone Y"
- **Maker-role grant** — bundled with approval; auto-grant on approve, auto-revoke if rejected/expired
- **Risk tier** — AI Builder proposes; human confirms (Stage 4); **frame as internal policy, not OCC 2026-13 mandate** (see Section 6)
- **Sponsor / approver routing** — parallel where independent; tier-gated for MRM (firm policy)
- **Records / evidence** — every state change → `fsi_IntakeDecisionLog` with hash chain + Purview 7-year retention label + nightly export to immutable blob storage

### Data model
- 9 entities from R2 (`fsi_IntakeRequest`, `fsi_IntakeDataSource`, `fsi_IntakeAction`, `fsi_IntakeRiskSignal`, `fsi_IntakeReview`, `fsi_IntakeApproval`, `fsi_IntakeDecisionLog`, `fsi_IntakeDuplicateMatch`, `fsi_IntakeHandoff`)
- Optional FK to existing `Innovation Backlog Idea` for backwards compatibility

### Productivity accelerators (highest leverage first)
1. **Auto-approve Tier-3 + Zone-1 + no-risk-signal** with sponsor sign-off (most Agent Builder requests flow through in minutes)
2. **AI Builder classifier** for risk signals (NPI, MNPI, PCI, PHI, COI, cross-border, regulated communication, suitability, trade/credit decision)
3. **Duplicate detection** against intake history + PPAC Agent Inventory
4. **DSPM-for-AI sensitivity lookup** during triage
5. **Parallel review routing** (InfoSec + Privacy + Compliance in parallel, not serial)
6. **Auto-handoff payload** to existing `agent-registry-automation` + auto-provision via Foundry / Copilot Studio API + auto-mint Entra Agent ID (GA May 1, 2026)

### Anti-patterns to avoid
- Long static form upfront (use progressive disclosure)
- Serial approvals where parallel is safe
- "Required for compliance" jargon in maker-facing copy (use plain English)
- Manual tier assignment without AI assist
- Storing intake records anywhere outside Dataverse (no SharePoint lists, no Excel)
- Using OCC 2026-13 / SR 11-7 as the **stated reason** for tier-gating generative AI (it's now firm policy, not regulator-mandated for gen AI)
- Building one channel only (multi-surface is essential)
- Leaving denial unconstructive (always suggest alternatives + appeal)
- No save-and-resume (kills 3-5 min target)

---

## 8. Decision-blocking questions (organized by stakeholder)

### For you (product owner)
1. **Solution boundary:** Should this `agent-intake` solution depend on the existing CoE Starter Kit Innovation Backlog being installed in the firm's tenant, or be standalone? (R2 recommends "extend with FK"; standalone is more portable.)
2. **Auto-approval threshold:** Are you comfortable with Tier-3 + Zone-1 + no-risk-signal requests **auto-approving** with only sponsor sign-off (no compliance/security review)? This is the single biggest productivity lever but requires policy comfort.
3. **Agent type scope confirmation:** Confirm intake covers all five (Copilot Studio + Agent Builder + declarative + custom engine + Foundry) — not Microsoft-only. Some firms might want to defer Foundry/pro-dev to a separate intake.
4. **Conversational agent priority:** Build Power Pages first, then Copilot agent (R2 recommendation), or build Copilot agent first as the primary surface (your stated preference)? Hybrid is feasible but build order matters.
5. **OCC 2026-13 framing:** Given the new guidance excludes generative/agentic AI from MRM scope, do you want to keep tier-gated MRM as **firm policy** (recommended) or relax it for generative agents?
6. **Records retention:** Standardize on **7 years** (R2's recommendation, absorbs worst-case across SEC 17a-4, FINRA 4511, CFTC 1.31), or follow the firm's existing records-management standard?
7. **Solution catalog placement:** Add `agent-intake` to the 35-solution suite as solution #36, or stage it as `agent-intake` v0.1.0-preview while we validate?

### For IT admin / Power Platform team
8. Is the **CoE Starter Kit Innovation Backlog** currently installed in your tenant? (Affects extend-vs-standalone decision.)
9. Do you have **AI Builder licensing** in the target environment? (Required for risk-signal classifier.)
10. What is your current **DLP policy posture** — block-by-default with allow-list, or allow-by-default? (Affects auto-DLP-impact analysis design.)
11. Is **Microsoft Purview DSPM-for-AI** licensed and active? (Optional but enables sensitivity lookup at triage.)
12. Will you adopt **Microsoft Agent 365 / Entra Agent ID Governance** at GA on May 1, 2026 ($15/user/mo or E7)? Affects whether handoff includes Agent ID minting.
13. Power Platform environment topology — do you have separate environments per governance zone today, or one shared dev environment?

### For security / compliance
14. **Tiering policy:** Approve our proposed Tier 1/2/3 + Zone 1/2/3 framework (Microsoft's published Citizen / Partnered / Professional model + SR 11-7-style tiers) as firm policy, given OCC 2026-13 makes it discretionary for gen AI?
15. **Sponsor evidence requirement:** Is sponsor signature with Entra OID + timestamp + payload hash sufficient, or does the firm require a separate e-signature platform (DocuSign, Adobe Sign)?
16. **Immutable storage choice:** Azure Storage with immutable blob policy (R2 recommendation) acceptable, or does the firm mandate a specific WORM-compliant store?
17. **Reviewer roles:** Confirm the six reviewer roles (Sponsor, Business Owner, InfoSec, Privacy, Compliance, MRM). Add Legal? Records Mgmt? Procurement (for vendor data)?
18. **Auto-approval policy:** Approve auto-approval for Tier-3 + Zone-1 + no-risk-signal with sponsor sign-off only? If not, what is the minimum review for the lowest-risk requests?
19. **Cross-border treatment:** Hard-block cross-border data flows at intake, or allow with extra approval?

### For Microsoft / vendors (validation calls)
20. CoE Starter Kit Innovation Backlog roadmap — is Microsoft planning a refresh or are we extending a frozen artifact?
21. Microsoft Agent 365 / Entra Agent ID Governance GA on May 1, 2026 — confirm tenant licensing path and APIs are stable for our handoff dependency.
22. Compliance Hub on Power CAT Copilot Studio Kit — any roadmap for pre-build approval workflows, or stay post-creation?
23. AvePoint AgentPulse — public pre-build approval workflow API, or post-discovery only? (Determines complement-vs-replace.)
24. ServiceNow AI Control Tower webhook for receiving approvals from a non-SN system of record? (Determines bidirectional integration design.)

---

## 9. Open assumptions (flagged for confirmation)

| # | Assumption | Source |
|---|---|---|
| OA1 | Firm uses Power Platform / Dataverse as the primary low-code platform (not ServiceNow as system of record) | Repo context |
| OA2 | Firm has an existing Power Platform CoE environment | R2 + repo context |
| OA3 | Firm has Entra ID Governance (P2) licensing for sponsor access reviews | R2 |
| OA4 | Firm's MRM team uses an internal GRC system with API access | R2 |
| OA5 | Firm wants conversational Copilot Studio intake agent (per your earlier stated preference) | Plan checkpoint |
| OA6 | Firm has Power BI Premium or Pro for dashboards | R2 |
| OA7 | The 35-solution suite's `agent-registry-automation` will accept a typed handoff payload from `agent-intake` | Repo context |
| OA8 | Conversational intake agent will be a M365 Copilot **declarative** agent (not a Copilot Studio classic agent) for the friendliest UX | R2 + counter-research |
| OA9 | OCC 2026-13's exclusion of gen/agentic AI from MRM is acceptable to the firm's CRO, who would still want internal tiering policy | Counter-research |

---

## 10. Recommended next step

**Recommended:** Answer the 24 decision-blocking questions in Section 8 (in one pass), then proceed directly to Phase B (build).

**Rationale:**
- We have **two converging research reports** with a clear Option B recommendation.
- The synthesized "best-of" design (Section 7) is implementable as-is.
- Counter-research surfaced **two material corrections** (OCC 2026-13 gen-AI exclusion; Entra Agent ID GA on May 1, 2026) that strengthen, not weaken, the recommendation.
- The remaining unknowns are firm-policy choices, not technical research gaps.

**Alternative:** If any answer surfaces a major gap (e.g., "we don't have AI Builder", or "the firm requires a vendor product"), we can commission a focused second-round mini-research on that one gap rather than redoing the whole study.

---

## Appendix A — Mapping to our 35-solution suite (handoff contracts)

| Existing solution | Intake hands off | Contract |
|---|---|---|
| `agent-registry-automation` | Approved request | Typed payload: request_id, agent_type, sponsor_oid, tier, zone, conditions, audit_pointer |
| `environment-lifecycle-management` | "Provision new env in zone X" decision | Trigger: zone, tier, requestor, sponsor |
| `conditional-access-automation` | Maker role grant condition | Trigger: maker_oid, zone, tier |
| `model-risk-management-automation` | Tier 1/2 routing | Trigger: request_id, tier, evidence_pack |
| `compliance-dashboard` | Continuous evidence | Source: `fsi_IntakeDecisionLog`, `fsi_IntakeApproval`, attestation pack |
| `cross-tenant-external-sharing-governance` | Cross-border data signal | Trigger: cross_border_flag, country_of_processing |
| `unrestricted-agent-sharing-detector` | n/a (post-creation) | Reads agent_id from handoff |

## Appendix B — Council review notes alignment

This Fit Assessment respects the council-review lessons learned from the 2026-04-16 review:
- Uses "Microsoft Entra ID" never "Azure AD"
- Uses "supports compliance with" / "helps meet" never "ensures compliance" / "guarantees"
- Verifies all column names will be defined in `create_fsi_intake_dataverse_schema.py` as canonical source of truth (logical names: `fsi_intakerequest`, etc., NOT `fsi_intake_request`)
- Will create `.ralph-config.json` with domain facts before any session work begins
