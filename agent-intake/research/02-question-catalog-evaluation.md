# Catalog Evaluation — Claude Sonnet 4.6 Thinking (Standalone)

**Date:** 2026-04-30  •  **Branch:** `feat/agent-intake-research`  •  **Source:** `files/catalog-report-1-claude-FULL.md`

---

## 0. Headline

| | |
|---|---|
| **Verdict** | **Adopt with targeted modifications** — promote to v1 working catalog after fixing 6 specific issues |
| **Why** | Hits the design brief on every dimension; FSI regulatory framing is current; auto-detect playbook is concrete enough to implement; anti-patterns are useful; gaps with vendor templates are credible; 12 decisions are all over-supported (≥10 questions each) |
| **Confidence** | High on questions and disqualifier logic; medium on auto-detect API call shapes (3 endpoints need verification before we depend on them) |
| **Risk if adopted as-is** | Two bugs — wrong default on HITL (CT-007) and wrong routing on SoD self-disclosure (MR-008) — would survive into v1 form. Also a zone-numbering convention conflict with our locked design decisions that needs resolving before form build. |

---

## 1. Scorecard (criteria A-J, 1-5)

| Criterion | Score | Rationale |
|---|---|---|
| **A. Coverage completeness** | **5** | 137 questions across all 12 decision categories; coverage matrix in Section 4 shows ≥10 questions per decision (densest: Decision 2 Controls = 37, Decision 8 Connectors = 34) |
| **B. Question quality** | **4** | Wording is consistently neutral and maker-friendly; uses YES/NO/Not-sure where uncertainty is plausible; compound questions are mostly avoided. Two specific quality bugs (CT-007 wrong default, MR-008 wrong routing) drop one point. |
| **C. Decision linkage** | **5** | Every question has a "Decisions Driven" column with cross-references; the Section 4 matrix makes it auditable and shows no decision is under-supported |
| **D. Auto-detection accuracy** | **3** | 43 questions auto-detect (31% of catalog) — generous and correctly thought through. APIs and OAuth scopes look right for Microsoft Graph (`/licenseDetails`, `/manager`, `/servicePrincipals`, `/applications`, `/applications/{id}/federatedIdentityCredentials`), Azure RBAC, and Power Platform Admin (`/environments`, `/connections`). Three endpoints are likely-wrong or speculative and need verification: **(i)** Purview catalog API path (`/catalog/api/search/query`) — endpoint structure looks invented; the actual Purview data-map search API uses different paths; **(ii)** Power Platform DLP endpoint `/apiPolicies` — actual is `/policies`; **(iii)** Federated credential issuer `https://token.botframework.com/` — plausible for Copilot Studio bot identities but speculative for general Power Platform managed identities. |
| **E. FSI regulatory fit** | **5** | Correctly cites **OCC Bulletin 2026-13** with the **explicit gen/agentic-AI exclusion** (matches our counter-research); correctly leaves SR 11-7 operative at the Federal Reserve; frames MRM as **firm policy** for gen AI (matches our locked decision #4); cites FINRA 3110/4511/2210/24-09/25-07, SEC 17a-4(f) WORM, CFTC 1.31, GLBA 501(b), SOX 302/404, HIPAA, PCI DSS v4.0, GDPR Art. 35/44-46, NYDFS 23 NYCRR 500, NIST AI RMF, ISO/IEC 42001. No over-claims, no invented rules. |
| **F. Disqualifier logic soundness** | **4** | Five platforms covered with HARD vs SOFT disqualifier distinction. Tier-1 force rule is sound (RT-001 OR RT-005 OR RT-003>1M OR DS-017). **Auto-approve rule reads `Tier=3 AND Zone=3 (Personal)`** — semantically correct (lowest-risk wins) but uses opposite numbering convention from our locked decision (we wrote "Tier-3 + Zone-1"). One of us has it inverted; needs reconciliation (see Section 6). OQ-007 self-flags an unrelated edge case (Tier-3 + Enterprise zone for public-info FAQ bot). |
| **G. Anti-patterns coverage** | **5** | 12 anti-patterns with concrete replacement guidance; each named against actual templates (CoE Starter Kit Innovation Backlog, ServiceNow AI Control Tower, Salesforce Agentforce ADLC). Strongest: AP-001 (don't ask makers their own tier), AP-005 (don't ask makers to name the platform), AP-011 (don't ask what systems can detect), AP-007 (don't lead with AUP attestation). Useful pattern. |
| **H. Coverage of our 12 must-include topics** | **5** | All 11 covered: data residency (EP-001), cross-border (DS-011, EP-002), MNPI (CT-002, DS-003), customer-facing (RT-004, ZN-004, CT-006), autonomous action (AT-001), financial-transaction authority (RT-001, DS-017), SoR integration (DS-016, RT-009), agent-to-agent (AT-007, CD-005), deprovisioning trigger (OH-003, OH-004), ownership transfer (MR-005, OH-005), KPIs (BJ-004, OH-006) |
| **I. Persona routing accuracy** | **4** | Maker / Sponsor / InfoSec / Privacy / Compliance / MRM / Records / Legal / Procurement all used appropriately. **One bug**: MR-008 (SoD conflict self-disclosure) is "Asked of: Maker + Sponsor" but a conflicted maker has no incentive to self-disclose; should be Sponsor-primary or auto-flag from HRIS attribute lookup. **One soft issue**: System-asked questions (CT-016, CT-017, RR-007, RR-008, OH-008, OH-009, EP-011, SP-004, SP-005) should still surface their auto-set value to the human approver as read-only — not vanish. |
| **J. Stage placement** | **4** | Stage 2 Capture / Stage 3 Auto-classify / Stage 5 Review used appropriately for ~95% of questions. A few that say "Stage 3 Auto-classify, System" but feed downstream review (e.g., RR-004 Purview label is Stage 5 Records selection — correct; RR-007/008 retention auto-set Stage 3 — correct as policy default). MR-006 row in Part 1 is missing a Stage value (truncation artifact only — fixed in Part 2). |
| **Total** | **44 / 50** | Strong report. |

---

## 2. Adoption verdict per category

| Category | Verdict | Notes |
|---|---|---|
| **AT — Agent Type (10)** | **Adopt as-is** | Disqualifier-aligned, complete, neutral |
| **CT — Controls (17)** | **Adopt with 1 fix** | Fix CT-007 default (see Section 4) |
| **EP — Environment Placement (12)** | **Adopt as-is** | Strong DLP + capacity + DR coverage |
| **RT — Risk Tier (10)** | **Adopt as-is** | Solid SR 11-7-style signals, $ banding clear |
| **ZN — Zone (6)** | **Adopt with numbering reconciliation** | Resolve Zone-1=Personal vs Zone-1=Enterprise convention with our locked decision |
| **SP — Sponsor (10)** | **Adopt as-is** | Parallel-vs-serial review captured (SP-010); MRM/Privacy/Compliance/Legal/Procurement all distinct |
| **MR — Maker Role (8)** | **Adopt with 1 routing fix** | Re-route MR-008 SoD self-disclosure away from Maker as primary |
| **DS — Data Source / Connector / Action (20)** | **Adopt as-is** | Most thorough section; covers RAG item-level perms (DS-015), licensed-feed restrictions (CD-008 cross-ref), Graph app permissions, ServiceNow/Jira |
| **RR — Records / Retention (10)** | **Adopt as-is** | 7-year default matches locked decision #5; SEC 17a-4(f) WORM flag included; CFTC 1.31 covered |
| **OH — Operational Handoff (12)** | **Adopt as-is** | Entra Agent ID minting at OH-012 matches locked decision #8; SLA-by-tier in OH-001 is a nice add |
| **CD — Conflicts / Dependencies (10)** | **Adopt as-is** | Includes CD-008 licensed-data-feed AI-restriction check (best find in the report) |
| **BJ — Business Justification (12)** | **Adopt with 1 question added** | BJ-005 ROI is optional — fine — but no question on whether this is a **new intake vs modification** of an existing approved agent (see Section 3) |

---

## 3. Coverage gaps to fill (questions Claude missed)

| Proposed ID | Question | Why it matters |
|---|---|---|
| **BJ-013 (new)** | Is this a new agent, or a modification / version-bump / scope-extension of an already-approved agent? | Modifications follow an abbreviated review track that re-uses the prior decision pack. Without this question, every modification re-runs the full intake — wasteful and noisy. |
| **AT-011 (new)** | What is the planned foundation-model selection (e.g., GPT-5, GPT-5-mini, Claude, Mistral, on-prem)? | Model selection drives capacity, cost, data-residency, and Procurement vendor-due-diligence (for non-Microsoft models). Claude's catalog has BYO-LLM as YES/NO (AT-002) but not which model. |
| **CT-018 (new)** | Will this agent fine-tune the underlying model on firm data (vs. RAG-only / prompt-engineered)? | Fine-tuning creates training-data lineage obligations (GLBA 501(b), Reg FD MNPI containment) and changes MRM scope dramatically. Currently absent. |
| **OH-013 (new)** | Will this agent be deployed in a sovereign cloud (GCC, GCC-High, DoD) or commercial M365? | Sovereign cloud has different feature parity (some Copilot Studio / Foundry features unavailable), different DLP connector lists, and different identity surfaces. EP-001 covers US-residency but not cloud-tier. |
| **CT-019 (new)** | If this is a voice-channel agent (AT-003=Voice), do callers require explicit consent that they are interacting with an AI (and that the call may be recorded for records purposes)? | Many state laws (CA, IL, FL) require disclosure; FINRA 25-07 emphasizes disclosure. RR-009 covers retention, but consent-at-interaction is separate. |
| **CD-011 (new)** | Is this agent built in-house, sourced from a Microsoft AppSource / ISV marketplace listing, or commissioned from an SI / contractor? | Source-of-build drives Procurement vendor-due-diligence (SP-006), license auditing, and IP/code-ownership review. Currently no procurement-origin question. |
| **RT-011 (new)** | Will the agent's outputs be used to train other AI systems (downstream model training, evaluation set, RLHF)? | Output reuse for training is a separate governance event (data lineage, IP rights, regulatory disclosure) that is invisible at intake otherwise. |
| **OH-014 (new)** | Will the agent be integrated with the firm's Microsoft Sentinel / SOC monitoring rules for anomaly detection? | OH-002 picks the log destination; OH-014 confirms the SOC rules are written. Without this, logs accumulate but no one is looking. |

**Net additions: 8 new questions → catalog v1 = 145 questions.**

---

## 4. Quality issues to fix (specific question IDs)

| ID | Issue | Fix |
|---|---|---|
| **CT-007** | HITL gating multi-select with default "No actions require approval" — least-privilege default is wrong way around | Change default to "All write/delete/send-external/financial-transaction actions require approval"; require explicit override to lower it |
| **MR-008** | SoD conflict-of-interest self-disclosure routed to "Maker + Sponsor" — conflicted makers will not self-disclose | Re-route to "Sponsor + auto-check from HRIS role attributes". Maker can answer informationally but the binding answer is Sponsor's. |
| **AT-009** | M365 Copilot license check labeled "Partial" auto-detect | Upgrade to "Yes" — Graph `/users/{id}/licenseDetails` returns the full SKU list deterministically; for population-level use group-membership lookup. No partial. |
| **AT-002 example LLMs** | References "GPT-4o, Phi" as Microsoft-hosted models | Update to "GPT-5, GPT-5.5, Phi-4" (current as of April 2026) |
| **References to "M365 Copilot Sydney orchestrator"** (AT-001, AT-004 reasoning text) | "Sydney" was the Bing Chat preview codename, not the current M365 Copilot orchestrator name | Replace with neutral phrasing: "the M365 Copilot orchestration runtime" |
| **CT-015** | Customer-content abuse-monitoring opt-out routed to "Asked of: InfoSec / Privacy" but stage is Stage 2 Capture | Either move to Stage 5 Review (correct stage for InfoSec/Privacy decision) or keep Stage 2 with maker informational disclosure + Stage 5 binding decision |

---

## 5. Auto-detect verification checklist (before we depend on these APIs)

Confirm these endpoints exist and have the documented response shape **before** the auto-detect playbook is operationalized:

| Question | API Claim | Verification |
|---|---|---|
| AT-009, MR-002, MR-003 | `GET https://graph.microsoft.com/v1.0/users/{id}/licenseDetails` | ✅ Confirmed live; standard Graph v1 endpoint |
| MR-001 | `GET https://api.bap.microsoft.com/.../environments?$filter=...` | ✅ Confirmed; Power Platform Admin API |
| MR-004 | Azure RBAC `/roleAssignments?$filter=assignedTo(...)` | ✅ Confirmed; standard Azure RBAC endpoint |
| MR-007, OH-012 | `GET /v1.0/servicePrincipals?$filter=displayName eq '{name}'` | ✅ Confirmed |
| SP-001 | `GET /v1.0/users/{id}/manager` | ✅ Confirmed |
| SP-003 | `GET /v1.0/users/{id}?$select=department,companyName,...` | ✅ Confirmed |
| DS-008 | `GET /providers/Microsoft.PowerApps/environments/{id}/connections` | ✅ Confirmed |
| DS-012 | `GET /v1.0/applications/{id}/requiredResourceAccess` | ✅ Confirmed |
| OH-012 federated credential | `POST /v1.0/applications/{id}/federatedIdentityCredentials` | ✅ Confirmed; **but** issuer `https://token.botframework.com/` is Bot-Framework-specific and may not apply to all Power Platform managed identities — confirm before depending on |
| **CT-012, DS-002 — Purview catalog API** | `GET https://purview.microsoft.com/catalog/api/search/query` | ⚠️ **Verify** — this URL pattern looks invented. The actual Purview data-map search API uses paths like `/datamap/api/search/query` or `/governance/v1/...`. Confirm exact GA endpoint. |
| **EP-010 — Power Platform DLP listing** | `GET https://api.bap.microsoft.com/.../scopes/admin/apiPolicies` | ⚠️ **Verify** — actual endpoint is `/policies` not `/apiPolicies`. Response shape correct. |
| RR-004 | `GET https://graph.microsoft.com/beta/security/labels/retentionLabels` | ⚠️ **Verify** — Microsoft has been shipping records-management Graph endpoints behind multiple paths over the past 2 years; confirm current GA path. |

**Action:** before any auto-detect logic is wired into the form, do a 30-min spike to call each ⚠️ endpoint with a real token in a sandbox tenant. If the endpoint is wrong, mark the question "No (manual)" instead of "Partial" — do not let the form claim auto-detect that fails silently.

---

## 6. Counter-research items (claims to verify or reconcile)

| Claim | Source in report | Verification status / required action |
|---|---|---|
| OCC 2026-13 excludes gen/agentic AI from regulatory MRM scope | Throughout (CT-005, SP-004, OQ-003) | ✅ Already verified in our prior counter-research — accurate |
| SR 11-7 remains operative at the Federal Reserve | OQ-003 implication | ✅ Verified |
| Entra Agent ID is GA May 1, 2026 | OQ-004 | ✅ Verified — GA tomorrow |
| FINRA Notice 25-07 introduces additional supervision/recordkeeping requirements that may need new questions | OQ-002 | ⚠️ Open — flagged correctly as an item for the firm CCO. Worth a 30-min read of the Notice text before form build. |
| Microsoft Entra Agent ID Administrator role mis-scoping CVE / security advisory (April 2026) | AT-007, CD-005, DS-012, DS-018, OH-012 reasoning text | ⚠️ **Verify** — referenced as "Microsoft patched an 'agent-only' role that was not (CSO Online, April 2026)". If this CVE is real, our `agent-access-monitor` solution should already track it; if invented, the citation needs to be removed. **Spot-check before form build.** |
| Microsoft Purview DSPM-for-AI is GA | OQ-010 | ⚠️ Open — Claude self-flagged as needing confirmation. As of April 2026 the public docs show DSPM-for-AI in GA but specific API surfaces vary. |
| **Zone numbering convention** (Zone 1 = Enterprise / highest-risk, Zone 3 = Personal / lowest-risk) | TIER-3-AUTO-APPROVE rule, ZONE-1-FORCE rule, ZN-001 reasoning | ⚠️ **Resolve with our locked design** — our locked decision #1 reads "auto-approve for **Tier-3 + Zone-1**", but our zone model wording was "Zone 1/2/3 (Personal/Team/Enterprise)" — i.e. Zone-1 = Personal. Claude inverts this (Zone-1 = Enterprise). Both are coherent internally but they conflict. **Industry convention favors Claude's mapping** (high-risk = low-numbered tier/zone). Recommend: adopt Claude's convention and amend our locked decision to read "Tier-3 + Zone-3 (Personal)". |

---

## 7. Final consolidated "blessed catalog" v1 — what's in scope

For the eventual Phase B form build (paused per locked decision):

- **137 Claude questions** with the 5 quality fixes from Section 4 applied
- **+8 author additions** from Section 3 → **145 questions total**
- **43 auto-detect** (after Section 5 verification — could be 40-43 depending on Purview/DLP endpoint outcomes)
- **102 maker-facing** questions requiring human judgment
- **6 anti-patterns codified** as form-builder rules (e.g., never let user pick tier; never lead with AUP)
- **5 disqualifier rule sets** for the 5 platforms (with our zone-numbering convention applied)
- **2 combined override rules**: TIER-1-FORCE and TIER-3-AUTO-APPROVE
- **10 Open Questions** routed to firm stakeholders (CPO, CCO, MRM Committee, MS account team, Records Management, AI Governance Committee, IPS Lead, Identity Lead) — we should bundle these as the first batch of pilot-firm conversations

**Out of scope this round** (deferred to Phase B):
- Question-rendering rules (which questions appear on the same form page)
- Conditional-show logic (which questions appear/hide based on prior answers)
- Save-and-resume mechanics
- Maker-friendly UX copy (the "Why it matters" column is currently compliance-officer voice — we'll need a maker-voice rewrite at form build time)
- Localization

---

## 8. Recommended next step

**Recommended:** Commit Claude's report and this evaluation to the branch (research artifacts only — solution scaffold remains paused per locked decision #7), and queue the 6 fixes + 8 additions + 3 endpoint verifications as a Phase B prerequisite checklist.

**Alternative:** Dispatch a second model (GPT or another) on the same prompt for cross-comparison if you want to validate that Claude's 137-question structure isn't anchored to a single model's training-data biases. This would add ~1 hour of evaluation but might surface 5-15 additional questions and reveal blind spots.

---

## Appendix — One-line summary per Open Question (Claude's OQ-001 to OQ-010)

| OQ | For | Resolve before |
|---|---|---|
| OQ-001 | CPO | Form build (affects Privacy review routing) |
| OQ-002 | CCO | Form build (may add 3-10 questions to CT/SP) |
| OQ-003 | MRM Committee | Form build (defines what triggers MRM) |
| OQ-004 | MS Account Team | Auto-detect playbook activation |
| OQ-005 | CCO + Legal + Records | RR-003 form rule writing |
| OQ-006 | NY Compliance | Only if firm is NYDFS-regulated |
| OQ-007 | AI Governance Committee | Form build (auto-approve scope) |
| OQ-008 | Identity Platform Lead | Form build (CT auto-controls when AT-007=Yes) |
| OQ-009 | Records Management | Form build (variable retention per agent) |
| OQ-010 | MS Account Team | Auto-detect playbook activation |
