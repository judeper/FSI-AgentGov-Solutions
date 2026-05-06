# Research Prompt — Intake Question Catalog for FSI Agent Governance

**Purpose:** Drive a research agent to produce the complete catalog of questions an IT admin must answer at intake to make every downstream decision (agent type, controls to enable, environment placement, and all related details) for an AI agent request in a US Financial Services firm.

---

## Prompt (paste into research agent)

You are a Senior AI Governance Architect with 12+ years designing intake and onboarding processes for regulated technology in US Financial Services (broker-dealers, banks, asset managers, insurers). You have deep expertise in Microsoft Power Platform, Microsoft 365 Copilot, Copilot Studio, Microsoft Agent Builder, declarative agents, custom-engine agents, Azure AI Foundry, Microsoft Entra Agent ID, Microsoft Purview, FINRA / SEC / OCC / Federal Reserve / CFTC / GLBA / SOX rules, and the Microsoft Power Platform CoE Starter Kit.

### Mission

Produce the **complete, deduplicated question catalog** that an IT admin (or an automated intake form) must collect from a maker requesting a new AI agent so that downstream decisions can be made **without back-and-forth**. Group every question by the decision it drives. Flag every question whose answer can be **auto-detected** from M365, Microsoft Graph, Microsoft Purview, Power Platform Admin Center, Microsoft Entra ID, or Microsoft Defender for Cloud Apps so the maker is **not** asked twice.

### Context (treat as fixed; do not redesign)

- **Firm type:** US Financial Services regulated entity (broker-dealer + bank + asset manager combinations are typical).
- **Regulatory baseline:** FINRA Rules 3110 (supervision), 4511 (books & records), 24-09 / 25-07 (AI guidance); SEC Rule 17a-3 / 17a-4 (records, including 17a-4(f) electronic-records WORM rules); OCC Bulletin 2026-13 (model-risk management — note this **excludes** generative & agentic AI from MRM scope and leaves it to firm policy); Federal Reserve SR 11-7 (still operative); CFTC 1.31 (records); GLBA 501(b) (safeguards); SOX 302/404 (controls); Reg FD; MNPI handling; suitability rules.
- **Platforms in scope (all five agent types):** (1) Microsoft Agent Builder in M365 Copilot, (2) Microsoft Copilot Studio classic agents, (3) Microsoft 365 Copilot **declarative** agents, (4) Copilot Studio **custom-engine** agents (BYO LLM), (5) Microsoft Azure AI Foundry / pro-developer agents.
- **Existing solution suite the intake hands off to:** `agent-registry-automation`, `environment-lifecycle-management` (zone-based provisioning), `conditional-access-automation`, `model-risk-management-automation`, `compliance-dashboard`, `cross-tenant-external-sharing-governance`, `unrestricted-agent-sharing-detector`, `agent-365-lifecycle-governance`, `credential-oversharing-detector`, `agent-knowledge-source-scanner`, `dlp-policies` style governance.
- **Locked design decisions** (do not re-litigate):
  - Standalone Power Platform / Dataverse solution (no CoE Innovation Backlog dependency)
  - Auto-approve Tier-3 + Zone-1 + no-risk-signal with sponsor sign-off + passive InfoSec sample-log
  - Tier-gated MRM as **firm policy** for all agent types (because OCC 2026-13 excludes gen/agentic AI from regulatory MRM)
  - 7-year retention on intake records
  - Maker UX order: Power Pages portal → M365 Copilot declarative agent → Teams sponsor app
  - Microsoft Entra Agent ID is feature availability should be verified in the target tenant/cloud — auto-mint at handoff
  - Tier model 1/2/3 (highest/medium/lowest risk) and Zone model 1/2/3 (Personal / Team / Enterprise) are firm policy

### Decisions the question catalog must support

The catalog must collect every input needed to drive each of these decisions:

1. **Agent-type recommendation** — which of the five platforms is the right fit (Agent Builder vs Copilot Studio classic vs declarative vs custom-engine vs Foundry). Include the **disqualifier** questions that rule platforms out (e.g., "needs autonomous external action" rules out declarative).
2. **Controls / guardrails to enable** — DLP policy scope, content moderation, prompt shield, sensitivity-label honoring, customer-content abuse monitoring opt-out, generative AI feature toggles, agent feedback collection, transcript logging, knowledge source item-level permission scan, conditional access for the maker and the agent identity, file-upload restrictions, MIME type restrictions, inactivity timeout, session security, action confirmation / HITL gating, output supervision queue, hallucination tracking, RAG source validation, scope-drift monitoring, segregation of duties, sharing restrictions.
3. **Environment placement** — shared vs dedicated environment; if shared, which existing one; if dedicated, what type (Production / Sandbox / Developer / Teams), what region / data-residency constraint, what DLP policy group, what capacity profile (Dataverse storage, AI Builder credits, Power Platform requests, Copilot Studio messages), what ALM stage (dev / test / prod), what blast-radius isolation, what backup / DR posture.
4. **Risk tier (1/2/3)** — inputs to the SR 11-7-style firm-policy classifier (autonomy level, financial impact, customer-facing, regulated-decision involvement, restricted-data exposure, reversibility).
5. **Zone classification (1/2/3)** — Personal / Team / Enterprise (sharing scope, audience size, integration with regulated systems).
6. **Sponsor / approver routing** — sponsor identity, business-owner identity, MRM applicability, InfoSec / Privacy / Compliance / Legal / Records / Procurement applicability, parallel-vs-serial review eligibility.
7. **Maker role grant** — what Power Platform role(s), Copilot Studio role(s), Agent Builder access, Foundry RBAC, Entra group membership, Conditional Access requirement.
8. **Connector / action / data-source approval** — connector list with sensitivity classification, action list with side-effect classification (read / write / delete / send-external / financial-transaction), data-source list with classification (NPI / MNPI / PCI / PHI / customer / employee / public / restricted), cross-border data flow, third-party API endpoints, OAuth scopes.
9. **Records & retention** — what artifact types must be captured (transcripts, decisions, sponsor signature, evidence pack), retention period (default 7 yrs), Purview label, immutable storage destination.
10. **Operational handoff** — environment to provision (or reuse), Entra Agent ID to mint, monitoring / logging destination, success criteria, deprovisioning trigger (inactivity threshold, owner change, business-owner departure), ownership transfer plan.
11. **Conflicts and dependencies** — duplicate-agent check inputs (semantic-similarity seed text, owner / department, capability summary), upstream agent dependencies, downstream consumer expectations, integration with system of record (ServiceNow change records, Jira tickets, GRC platform).
12. **Business justification & success metrics** — problem statement, target user population size, expected usage frequency, KPIs / OKRs, ROI estimate, alternative considered.

### Sources to consult (do NOT invent or hallucinate)

- **Microsoft primary docs:** Learn pages for Power Platform admin, Copilot Studio admin, Agent Builder, declarative agents, custom-engine agents, AI Foundry, Entra Agent ID, Purview DSPM-for-AI, Power Platform DLP, environment strategy, capacity management, ALM hub.
- **Microsoft Power CAT:** Copilot Studio Kit (incl. Compliance Hub), CoE Starter Kit (Innovation Backlog, Maker Onboarding, Center of Excellence), Power Platform Well-Architected Framework, Cloud Adoption Framework AI scenario.
- **Microsoft AI governance assets:** `microsoft/Microsoft-AI-Decision-Framework`, `microsoft/agent-governance-toolkit`, Responsible AI Standard, Microsoft Trustworthy AI principles.
- **Vendor playbooks:** AvePoint AgentPulse, Credo AI, Holistic AI, ServiceNow AI Control Tower, Salesforce Agentforce ADLC, Google Agentspace / Gemini Enterprise.
- **Open source:** GitHub repos with intake / onboarding templates for low-code, AI, or RPA platforms; community discussions in Power Users community, Microsoft Tech Community, r/PowerPlatform, r/CopilotStudio.
- **Regulatory primary sources:** FINRA Notices 24-09 and 25-07, FINRA Rule 3110 / 4511, SEC Rule 17a-4 (incl. 2022 amendments), OCC Bulletin 2026-13 (replaces 2011-12 from Apr 17 2026), Federal Reserve SR 11-7, CFTC 1.31, NIST AI Risk Management Framework, ISO/IEC 42001, NYDFS Cybersecurity Reg 23 NYCRR 500 (insofar as it touches AI).
- **Analyst sources:** Gartner / Forrester guidance on AI agent governance and CoE patterns (cite report names; do not paywall-bypass).

### Output format (strict)

Produce a single Markdown document with these sections in order:

1. **Executive summary** — one paragraph: what was researched, how many questions in the catalog, how many auto-detectable, top three insights about coverage gaps in current Microsoft / vendor templates.
2. **Methodology** — sources actually consulted, search strategies, exclusions, confidence rating per source.
3. **Question catalog** — the deliverable. A flat table with these columns:
   - **ID** (e.g., `Q001`, namespaced by category: `AT-001` for Agent Type, `CT-001` for Controls, `EP-001` for Env Placement, `RT-001` for Risk Tier, `ZN-001` for Zone, `SP-001` for Sponsor, `MR-001` for Maker Role, `DS-001` for Data Source / Connector / Action, `RR-001` for Records / Retention, `OH-001` for Operational Handoff, `CD-001` for Conflicts / Dependencies, `BJ-001` for Business Justification)
   - **Category** (one of the 12 above)
   - **Question text** (maker-facing, plain English, no jargon)
   - **Why it matters** (one sentence, regulator-citation if applicable)
   - **Decisions it drives** (cross-reference to the 12 decisions list, e.g., "1, 3, 4")
   - **Answer type** (single-select / multi-select / free text / numeric / date / file upload / YES-NO / Likert)
   - **Allowed values** (if select-type) or **validation rule** (if free / numeric)
   - **Default** (or "n/a")
   - **Required?** (always / conditional-on-Qxxx / optional)
   - **Auto-detectable?** (Yes — from \[source\] / No / Partial — pre-fill from \[source\])
   - **Stage** (Stage 2 Capture / Stage 3 Auto-classify / Stage 5 Review)
   - **Asked of** (Maker / Sponsor / InfoSec / Privacy / Compliance / MRM / Records / Legal)
   - **Source citation** (where this question pattern was found, or "novel-by-author")
4. **Cross-cutting coverage matrix** — for each of the 12 decisions, list the question IDs that drive it. Flag any decision with fewer than 3 supporting questions (likely under-covered).
5. **Auto-detect playbook** — for every question marked Auto-detectable Yes/Partial, the exact Graph API / Power Platform Admin API / Purview API / Defender for Cloud Apps API call (or PowerShell cmdlet) that retrieves the value, with required scopes and sample response shape.
6. **Disqualifier rules** — the if-then logic that turns answers into agent-type rule-outs (e.g., "if BJ-003=needs-autonomous-external-action then declarative is OUT").
7. **Anti-patterns observed in other intake processes** — questions that should NOT be asked (leading, jargon-heavy, duplicates, untenable for makers to answer, questions where "I don't know" is the only honest answer).
8. **Coverage gaps in Microsoft / vendor / OSS templates** — what these existing templates miss that our catalog covers; what they cover that we should consider adding.
9. **Open questions for stakeholders** — anything the researcher could not resolve from public sources (e.g., "does the firm allow Tier-3 to bypass Privacy review?").
10. **Bibliography** — every source cited with URL, retrieval date, and a one-line annotation.

### Quality bar

- **No invented sources.** If a Microsoft Learn page does not exist, do not cite a fake URL. Mark as "no public source found".
- **No leading questions.** Wording must be neutral.
- **No questions answerable by auto-detect alone.** Every Maker-asked question must require human judgment.
- **No duplicates.** If two questions extract the same signal, merge them.
- **Maker-facing language.** No regulator jargon in the question text; the "Why it matters" column is where compliance language lives.
- **Coverage check.** Catalog must include at least one question for every one of the 12 decisions. Catalog must include questions specifically about: data residency, cross-border flow, MNPI handling, customer-facing exposure, autonomous action, financial-transaction authority, integration with systems of record, agent-to-agent communication, deprovisioning trigger, ownership transfer, KPIs.
- **Estimated final size:** 80–150 questions in the catalog (deduped). Larger means probably duplicated; smaller means probably missing coverage.

### What to deliver

A single Markdown document (target 12-25k words) following the format above. No rendered HTML / CSS visualizations — Markdown tables only. Save your work; we will iterate.
