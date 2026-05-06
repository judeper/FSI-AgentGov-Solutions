# Intake Form Design v1 — `agent-intake` solution

**Date:** 2026-04-30  •  **Branch:** `feat/agent-intake-research`  •  **Phase:** B-prep design (no code)

**Inputs:** `catalog-report-1-claude-FULL.md` (137-question catalog) · `catalog-evaluation-claude.md` (scorecard + fixes) · `fit-assessment.md` (7-stage canonical model + 9-entity Dataverse) · 8 locked product-owner decisions.

**Status:** Design ready for stakeholder walkthrough. Not yet a build spec — see Section 12 Open Questions.

---

## 0. Sidebar — zone numbering reconciliation (resolve before form build)

Our locked decision #1 reads "auto-approve for **Tier-3 + Zone-1** + no risk signal." That used a numbering convention where Zone-1 = Personal (lowest-risk). Both Claude's catalog and industry convention use the **inverse**: Zone-1 = Enterprise (highest-risk), Zone-3 = Personal (lowest-risk). Same direction as Tier (Tier-1 highest-risk).

**This document adopts the conventional mapping:**

| Zone | Audience | Sharing scope | Managed Env | Default DLP group |
|---|---|---|---|---|
| **Zone-1** | Enterprise / external / customer-facing | Org-wide or external | Required | Restricted-NPI |
| **Zone-2** | Team / department (20-500 users) | Cross-team but within firm | Required | Regulated-General |
| **Zone-3** | Personal (just the maker) | Maker only | Optional | Personal-Productivity |

**Locked decision #1 should now read:** "Auto-approve for **Tier-3 + Zone-3** + no risk signal + sponsor sign-off + passive InfoSec sample-log."

This document treats that as the operative wording.

---

## 1. Design principles

The form architecture is governed by six principles, in priority order:

1. **Risk-proportional depth.** A Tier-3 personal FAQ bot answers ~10 questions in ~3 minutes. A Tier-1 customer-facing trade-execution agent answers ~35 questions in ~20 minutes. Same form architecture, different depth, branching driven by 6 trigger questions answered first.

2. **Maker types business intent, not governance jargon.** Makers describe *what* the agent does, *who* uses it, *what data* it touches, and *why* the firm needs it. They never type "DLP policy group", "MRM tier", "retention class", "sensitivity label" — those are computed from their answers or set by IT policy once.

3. **System computes everything computable.** ~35 fields are derived by classification rules from maker answers. ~15 are looked up from IT-maintained policy tables. 43 are auto-detected from Microsoft Graph / Power Platform Admin / Purview / Entra. Only ~22-35 ever touch a human's keyboard per intake.

4. **IT reviews override-or-approve, not data entry.** When IT (or InfoSec, Privacy, Compliance, MRM, Records) is engaged, they see a pre-populated decision pack and click *Approve / Override / Reject*. They type only when overriding a system recommendation. For Express-path agents, IT is uninvolved entirely — sample audits and existing post-deployment governance solutions catch drift.

5. **Decision pack ≠ form.** The form is a UX artifact for the maker. The decision pack is the back-office record (FINRA 4511 / SEC 17a-4 evidence). All 137 fields land on the record regardless of which path the agent took. We record the same evidence; we just don't make humans type it.

6. **Adoption is the strategy.** A 137-question form has 0% adoption — makers route around it via shadow IT. A 10-question Express form with auto-approve has 80%+ voluntary adoption. The latter generates more compliance evidence than the former, because the former is empty.

---

## 2. The 6 trigger questions (answered first by every maker)

These six questions are the **first screen** every maker sees, regardless of intended path. Answers route the maker to Express, Standard, or Full path. None of the six are skippable.

| # | ID | Question (maker-voice) | Type | Answer drives |
|---|---|---|---|---|
| **T1** | ZN-001 | Who is the intended audience for this agent? | Single-select: *Just me* / *My team (≤20 people)* / *My department (20-500)* / *The whole firm* / *External customers or partners* | Zone classification |
| **T2** | AT-001 / RT-001 (combined) | What does the agent **do** to other systems? | Single-select: *Read-only — looks up information and answers questions* / *Sends email or messages* / *Creates or updates records (CRM, tickets, files)* / *Initiates a financial transaction (payment, trade, wire, fee)* / *Other* | Risk tier baseline + autonomous-action disqualifier |
| **T3** | RT-004 | Will customers see the agent's output (directly or via an employee passing it along)? | Single-select: *No — internal only* / *Yes — but a human reviews first* / *Yes — directly customer-facing* | FINRA 2210 supervision trigger |
| **T4** | CT-001 + CT-002 + DS-003 (combined) | Will the agent read or process any of these data types? (Check all that apply.) | Multi-select: *None of the below* / *Customer NPI (PII, account numbers, balances)* / *Material non-public information (MNPI / pre-trade research / undisclosed earnings)* / *Restricted licensed data (Bloomberg, FactSet, Refinitiv)* / *Employee personal data (HR, comp)* / *Public information only* | NPI/MNPI/licensed-data control auto-trigger |
| **T5** | RT-006 | Will the agent run on its own — on a schedule or in response to events — without a human watching each run? | Yes / No | Supervision class + scope-drift monitoring trigger |
| **T6** | RT-001 (sub-question to T2) | If the agent takes financial-transaction actions (T2 = "Initiates a financial transaction"), does a human approve **every** transaction before it executes, or are some transactions auto-executed by the agent? | Single-select: *Not applicable* / *Every transaction requires human approval* / *Some auto-execute up to a defined threshold* / *All transactions auto-execute* | Tier-1 confirmation + HITL gate strength |

### Routing rules (computed at end of trigger screen)

```
def route(answers):
    # FULL path triggers — any one forces full review
    if answers.T2 in ["Initiates a financial transaction"]:
        return "FULL"
    if answers.T3 == "Yes — directly customer-facing":
        return "FULL"
    if "Material non-public information" in answers.T4:
        return "FULL"
    if "Customer NPI" in answers.T4 and answers.T5 == "Yes":
        return "FULL"  # autonomous + NPI = always full
    if answers.T6 in ["Some auto-execute up to a defined threshold",
                      "All transactions auto-execute"]:
        return "FULL"

    # STANDARD path triggers
    if answers.T1 in ["My department (20-500)", "The whole firm"]:
        return "STANDARD"
    if answers.T2 in ["Sends email or messages",
                      "Creates or updates records",
                      "Other"]:
        return "STANDARD"
    if "Customer NPI" in answers.T4:
        return "STANDARD"
    if "Restricted licensed data" in answers.T4:
        return "STANDARD"
    if answers.T3 == "Yes — but a human reviews first":
        return "STANDARD"
    if answers.T5 == "Yes":
        return "STANDARD"

    # EXPRESS path — everything else
    # (Just-me OR small-team, read-only, internal, no NPI/MNPI/licensed,
    #  human-monitored or no actions)
    return "EXPRESS"
```

**Maker UX:** After answering the 6 triggers, the maker sees a one-line summary: *"Based on your answers, this is a low-risk personal productivity agent. You'll answer 4 more questions and your manager will approve in Teams. Estimated time: 2 more minutes."* — set expectations transparently.

**Override rule:** The maker cannot self-downgrade. If T2-T6 trigger Standard or Full, the maker must follow that path. Sponsors and InfoSec reviewers can override upward (escalate Express → Standard) but never downward.

---

## 3. Express path (~10 questions, ~3 minutes, auto-approve)

**When triggered:** Just-me or small-team, read-only or no actions, internal-only, no NPI / MNPI / licensed data, human-monitored. Approximately **60-70% of real-world intakes** in our experience benchmark.

**Total maker questions: 10** (6 triggers + 4 path-specific).

### Path-specific questions (after the 6 triggers)

| # | ID | Maker-voice question | Type | Notes |
|---|---|---|---|---|
| E1 | BJ-001 | What's a short name for this agent? (1-5 words) | Free text | Example: "Team policy lookup bot" |
| E2 | BJ-002 | In one sentence, what does the agent do for the user? | Free text | 200-char limit; example: "Answers questions about our travel policy from the SharePoint policy site." |
| E3 | DS-001 | What information does the agent need to read? (Tile picker, multi-select) | Tile gallery: *A specific SharePoint site* / *My OneDrive folder* / *A Teams channel* / *My mailbox* / *A Dataverse table* / *The web (public search)* / *Files I'll upload* | If the maker picks SharePoint, an inline picker resolves the URL. Item-level perms checked async per CT-012 / `agent-knowledge-source-scanner` |
| E4 | SP-001 | Who is your manager / business sponsor? | UPN picker | **Pre-filled** with the maker's manager from `Graph /v1.0/users/{id}/manager`; maker can change. |

### What the system computes (no maker input)

From the 10 maker answers, the system populates 37 fields automatically (see Section 6 for rules). Examples:

- `tier = 3` (no T2/T3/T6 triggers fired)
- `zone = 3` (T1 = "Just me" or "My team")
- `dlp_group = "Personal-Productivity"` (policy lookup: tier=3 + zone=3)
- `managed_env_required = false` (policy lookup: zone=3)
- `mrm_review_required = false` (tier=3)
- `privacy_review_required = false` (T4 has no NPI/MNPI/employee-data)
- `compliance_review_required = false` (no T2 actions, no T3 customer-facing)
- `infosec_review = "passive_sample_log"` (locked decision #1)
- `retention_class = "default_7yr"` (firm baseline)
- `entra_agent_id_required = true` (locked decision #8 — minted at handoff regardless of tier)

### Sponsor experience

Sponsor receives an **adaptive card in Microsoft Teams** with:

```
[Agent intake — sponsor approval needed]

📝 "Team policy lookup bot"
   Built by: Jude Pereira
   Reads from: HR Policies SharePoint site
   Audience: My team (≤20 people)
   Risk tier: 3 (low)  •  Zone: 3 (Personal)
   Path: Express auto-approve

In one sentence: "Answers questions about our travel policy from the SharePoint policy site."

By approving, you confirm:
  ✓ This use case is appropriate and aligns with the maker's role
  ✓ You will be the named accountable owner for ongoing operation
  ✓ You'll respond to access reviews every 6 months

[ Approve ]  [ Request changes ]  [ Reject ]
```

**1-click approval.** Sponsor types nothing. If sponsor clicks *Request changes*, an optional comment field appears.

### Auto-approval workflow

After sponsor approval:

1. System creates Entra Agent ID for the agent (per locked decision #8)
2. System provisions the agent in the appropriate development environment (or hands off to existing `agent-registry-automation`)
3. Maker receives Teams notification: *"Your agent is approved and provisioned. You can start building in [Power Platform / Agent Builder]. Compliance record retained for 7 years."*
4. Decision pack record committed to Dataverse with all 137 fields populated (10 by maker, 37 by computation, 15 by policy lookup, 43 by auto-detect, 32 left as N/A or default-empty for Express path — they're populated only on Standard/Full path)
5. **Passive InfoSec sample-log:** intake row added to the daily InfoSec sample queue. InfoSec selects ~10% to spot-audit; if anything looks risky, they can re-route the agent to Standard or Full review post-hoc (rare but possible).

### Express path SLA: same business day (typically <2 hours, sponsor-response-time bound).

### What if the agent's risk profile changes after deployment?

Existing FSI-AgentGov solutions detect post-deployment drift:

- `unrestricted-agent-sharing-detector` catches if the maker shares the Express-approved agent more broadly (escalates zone)
- `scope-drift-monitor` catches data-access drift beyond declared scope
- `agent-access-monitor` catches over-permissive sharing
- `agent-365-lifecycle-governance` catches sponsor departure / access-review failure

When any of these fire, the agent is **flagged for re-intake** at the appropriate higher path. Express is not a permanent free pass — it's a fast initial trust grant with active drift detection.

---

## 4. Standard path (~20 questions, ~7 minutes, sponsor + InfoSec sample)

**When triggered:** Department-wide or firm-wide audience, OR action-taking agent (sends email / writes records / other), OR NPI access, OR licensed-data access, OR human-reviewed customer-facing output, OR autonomous unmonitored operation.

**Total maker questions: 20** (6 triggers + 4 Express questions + 10 path-specific).

### Path-specific questions (Standard adds these to Express)

| # | ID | Maker-voice question | Type | Notes |
|---|---|---|---|---|
| S1 | DS-006 | Beyond what you picked above, list any other systems the agent will connect to. | Multi-select w/ free-text "Other": *Microsoft Graph (mail/calendar/files)* / *ServiceNow* / *Jira* / *Salesforce* / *Custom REST API* / *Database (SQL/Cosmos)* / *None* | If "Custom REST API" or "Database", auto-flag for InfoSec |
| S2 | DS-008 | Will the agent use any premium or custom Power Platform connectors? | Yes / No / Not sure | If Yes, system pulls connector list via PPAC API — maker confirms |
| S3 | CT-007 | For agents that take actions: which actions require a human to approve before they execute? | Multi-select with **default = "All write/delete/send actions require approval"** (least-privilege default) | Maker can lower the gate but the default is high-restriction |
| S4 | DS-015 | If the agent reads from SharePoint, does it use the **maker's permissions** to read content, or a **shared service account / managed identity** with broader access? | Single-select: *My permissions only* / *Service account / managed identity* / *Not sure* | Drives oversharing risk + Purview item-level scan trigger |
| S5 | RT-008 | Will the agent process **employee** personal data (compensation, performance, HR records)? | Yes / No | If yes → Privacy review required |
| S6 | OH-005 | Who is the back-up business owner if the primary sponsor (your manager) is unavailable for >2 weeks? | UPN picker | Continuity for access reviews + decision authority |
| S7 | BJ-004 | What's one measurable outcome you expect from this agent in the next 90 days? (e.g., "Reduce time-to-answer policy questions from 10 min to 1 min for 50 users") | Free text | Used for post-deployment value review at 90 days |
| S8 | BJ-013 (new) | Is this a brand-new agent, or a modification / version-bump / scope-extension of an existing approved agent? | Single-select: *New* / *Modification of: [picker of existing agents]* | Modifications follow abbreviated review track |
| S9 | OH-001 | What's the operational SLA you need? (uptime, response time) | Single-select: *Best-effort (no SLA)* / *Business hours availability* / *24/7 with <4hr recovery* | Drives environment selection + DR posture |
| S10 | RR-005 | Should the agent's conversation transcripts be retained beyond the firm baseline (7 years)? | Yes / No / Not sure → defaults to No, escalates to Records review if Yes | Most agents accept the 7-year baseline |

### What changes vs. Express

- **Sponsor card** includes a risk summary table (data sources, actions, NPI flag, sponsor accountability statements specific to FINRA 3110 supervision if T5=Yes or T2 takes actions)
- **InfoSec 10% sample-review** — InfoSec is automatically queued to review 1 in 10 Standard-path agents within 3 business days; can request changes or re-route to Full
- **Privacy review** auto-triggered if S5=Yes or T4 includes Customer NPI / Employee data
- **MRM review** *not* triggered for Standard (Tier-2 lite-review per locked decision #4 — Compliance handles, not MRM committee)
- **Decision pack** populates ~95 of 137 fields (10 maker + 10 path + 43 auto-detect + 35 computed + the rest from policy lookup or defaults)

### Standard path SLA: 3-5 business days

---

## 5. Full path (~35 questions, ~20 minutes, full parallel review)

**When triggered:** Financial-transaction agent, OR directly customer-facing (no human review), OR MNPI access, OR autonomous + NPI, OR auto-executing transactions.

**Total maker questions: 35** (6 triggers + 4 Express + 10 Standard + 15 path-specific).

### Path-specific questions (Full adds these to Standard)

| # | ID | Maker-voice question | Type | Notes |
|---|---|---|---|---|
| F1 | RT-002 | If the agent produces an incorrect or harmful output, can the effect be **fully reversed** without customer harm or regulatory consequence? | Single-select: *Fully reversible* / *Partially reversible (some effort)* / *Irreversible* / *Not sure* | Risk multiplier per SR 11-7 / ISO 42001 |
| F2 | RT-003 | What's the maximum estimated dollar impact if the agent malfunctions for one incident? | Single-select: *Under $10K* / *$10K-$1M* / *Over $1M* / *Not quantifiable* | Materiality scoring |
| F3 | RT-005 | Does the agent make — or directly feed into — a **regulated decision** (KYC, AML disposition, suitability determination, credit assessment)? | Yes / No / Partial | Triggers MRM committee review (firm policy) |
| F4 | RT-009 | Does the agent have **write or delete** access to any system of record (core banking, OMS, CRM, HRIS)? | Yes / No | SOX 404 implications + segregation-of-duties review |
| F5 | DS-017 | List every system the agent can write to or delete from. | Multi-select | Direct downstream of F4 |
| F6 | CT-006 | If T3 = customer-facing: what AI disclosure language will be shown to the customer? (FINRA 25-07 considerations) | Free text or *"Use firm default disclosure"* | Compliance-reviewed |
| F7 | AT-007 | Will this agent communicate with or delegate work to other agents (multi-agent orchestration, A2A)? | Yes / No / Planned future | Triggers Entra Agent ID delegation review per April 2026 advisory |
| F8 | CD-005 | If F7 = Yes: list the agents this one will call, and the agents that may call it. | Free text + linked agent IDs | A2A permission inheritance review |
| F9 | CT-019 (new) | If voice-channel: do callers receive explicit AI-disclosure consent + recording notice? | Yes / No / Not voice channel | State law (CA/IL/FL) + FINRA 25-07 |
| F10 | OH-014 (new) | Confirm: Microsoft Sentinel anomaly-detection rules will be written for this agent before go-live (or you'll work with the SOC team to scope them). | Acknowledged / Need help scoping | Avoids "logs accumulate, no one watches" anti-pattern |
| F11 | OH-007 | What is the kill-switch procedure if the agent must be stopped immediately? | Single-select: *Disable in Power Platform admin / Foundry portal* / *Revoke Entra Agent ID* / *Other (describe)* / *Need help defining* | Required for Tier-1 |
| F12 | OH-013 (new) | Will this be deployed in commercial M365, GCC, GCC-High, or DoD? | Single-select: *Commercial M365* / *GCC* / *GCC-High* / *DoD* | Drives feature-parity check + connector availability |
| F13 | CD-008 | Are any of the licensed data feeds the agent uses (Bloomberg, FactSet, Refinitiv, etc.) under a license that **prohibits AI/LLM ingestion**? | Yes / No / Don't know — need vendor confirmation | Procurement / Legal review trigger |
| F14 | CD-011 (new) | Is this agent built in-house, sourced from a Microsoft AppSource / ISV listing, or commissioned from an SI / contractor? | Single-select | Procurement vendor-due-diligence trigger if not in-house |
| F15 | BJ-012 (last) | Acceptable Use Policy attestation: I confirm I have read and will operate this agent in accordance with the firm's AI Acceptable Use Policy v[X]. | Acknowledged checkbox | **Placed last** per anti-pattern AP-007 (debiasing — never lead with AUP) |

### What changes vs. Standard

- **Full parallel review** activated per locked decision #4: InfoSec + Privacy + Compliance + MRM (firm policy) + Records + Legal + Procurement (if F14 ≠ in-house) all engaged simultaneously
- **Sponsor card** includes the full risk-tier rationale, MRM trigger basis, and explicit sign-off statements per FINRA 3110 Rule 3110(b) supervisory responsibility
- **MRM committee review** required (firm policy per OCC 2026-13 + SR 11-7 framing). Output: validation evidence, holdout-test results, vendor attestation if applicable.
- **Reviewer override workflow:** each reviewer sees the pre-populated decision pack + the maker's path-specific answers, and clicks Approve / Override / Reject per their domain. If any reviewer overrides a system-computed value, the override is logged with reviewer UPN + timestamp + rationale.
- **Decision pack** populates **all 137 fields** + the 8 author additions = 145 fields total

### Full path SLA: 2-4 weeks (depending on MRM committee cadence)

---

## 6. Auto-classification rules (~35 fields computed from maker answers)

These are the rules the system runs against maker answers to populate fields the maker never sees. Presented as decision-table pseudo-code suitable for translation to Power Automate / Dataverse business rules.

### 6.1 Risk Tier (most consequential computation)

```python
def compute_tier(answers):
    # Tier-1: highest risk
    if answers.T2 == "Initiates a financial transaction":
        return 1
    if answers.T6 in ["Some auto-execute", "All auto-execute"]:
        return 1
    if "MNPI" in answers.T4:
        return 1
    if answers.T3 == "Yes — directly customer-facing":
        return 1
    if answers.RT_005 == "Yes":  # only asked on Full path; default No otherwise
        return 1
    if answers.RT_003 == "Over $1M":
        return 1
    if answers.RT_009 == "Yes":  # write/delete to SoR
        return 1

    # Tier-2: moderate risk
    if "Customer NPI" in answers.T4:
        return 2
    if answers.T2 in ["Sends email", "Creates/updates records"]:
        return 2
    if answers.T1 in ["My department", "The whole firm"]:
        return 2
    if answers.T5 == "Yes":  # autonomous unmonitored
        return 2
    if answers.RT_003 == "$10K-$1M":
        return 2

    # Tier-3: low risk
    return 3
```

### 6.2 Zone

```python
def compute_zone(answers):
    if answers.T1 == "External customers or partners":
        return 1  # Enterprise
    if answers.T1 == "The whole firm":
        return 1
    if answers.T3 == "Yes — directly customer-facing":
        return 1
    if answers.T1 == "My department (20-500)":
        return 2  # Team
    if answers.T1 == "My team (≤20 people)":
        return 2
    return 3  # Personal
```

### 6.3 Other computed fields (one-line rules)

| Field | Rule |
|---|---|
| `path` | `route(answers)` from Section 2 |
| `dlp_group` | Policy lookup (Section 7) keyed on `(tier, zone)` |
| `managed_env_required` | `zone <= 2` |
| `mrm_review_required` | `tier == 1` (firm policy per locked decision #4) |
| `privacy_review_required` | `"Customer NPI" in T4 OR "Employee personal data" in T4 OR S5 == "Yes"` |
| `compliance_review_required` | `tier <= 2 OR "MNPI" in T4 OR T3 != "No — internal only"` |
| `legal_review_required` | `F13 in ("Yes", "Don't know") OR F14 != "in-house"` |
| `procurement_review_required` | `F14 != "in-house"` |
| `records_review_required` | `S10 == "Yes" OR T4 contains regulated data` |
| `infosec_review` | tier=1 → "full"; tier=2 → "10% sample"; tier=3 → "passive sample-log" |
| `supervision_class` | `"FINRA-3110" if T5=="Yes" or T3 in ("Yes — direct", "Yes — human-reviewed") else "informal"` |
| `customer_disclosure_required` | `T3 != "No — internal only"` |
| `kill_switch_required` | `tier == 1` |
| `dr_required` | `S9 == "24/7"` OR `tier == 1` |
| `entra_agent_id_required` | `True` (always, per locked decision #8) |
| `worm_storage_required` | `T4 contains "MNPI" OR records_review fires "Yes" OR tier==1 with customer-facing` |
| `sponsor_routing` | `"serial" if tier==1 else "parallel"` |
| `auto_approve_eligible` | `tier==3 AND zone==3 AND no risk signals AND sponsor approves` |
| `sample_audit_queue` | `True if path=="EXPRESS" else False` |
| `scope_drift_monitor_enabled` | `True if T5=="Yes" OR tier<=2` |
| `prompt_shield_required` | `T2 != "Read-only" OR T3 != "No — internal only"` |
| `content_moderation_level` | `"high" if tier==1 else "medium" if tier==2 else "low"` |
| `transcript_logging` | `tier <= 2 OR T3 != "No — internal only"` |
| `feedback_collection` | `True for all` |
| `90day_value_review` | `True if S7 provided` |
| `next_access_review_date` | `today + 6 months` (sponsor recertifies) |
| `solution_dependencies` | computed from data-source picks → which existing FSI-AgentGov solutions activate (e.g., picking SharePoint → `agent-knowledge-source-scanner`) |
| `risk_score` | `weighted sum of tier(40%) + zone(20%) + autonomy(20%) + reversibility(20%)` — used for ranking in InfoSec dashboard |
| `tier_rationale` | auto-generated text explaining which trigger answer drove the tier (for audit trail) |
| `change_log_required` | `tier <= 2` (every config change retained) |

### 6.4 Override mechanism

Every computed field is **overridable** by an authorized reviewer during Stage 5:

- **InfoSec** can override: `dlp_group`, `managed_env_required`, `prompt_shield_required`, `content_moderation_level`, `infosec_review` strength
- **Privacy** can override: `privacy_review_required` (escalate or waive), `customer_disclosure_required`, retention period
- **Compliance** can override: `supervision_class`, `compliance_review_required`, `customer_disclosure_required` text
- **MRM Committee** can override: `mrm_review_required` strength, validation evidence requirements
- **Records** can override: `worm_storage_required`, retention period
- **Sponsor** can escalate (not de-escalate) tier or zone
- **Maker** can never override computed values

Every override is logged with reviewer UPN, timestamp, prior value, new value, and free-text rationale. Logs are immutable and retained 7 years.

---

## 7. Policy lookup tables (~15 fields, set once by IT)

These tables are maintained centrally by the IT governance team, NOT per-agent. They're presented here as YAML for portability; in production they live in Dataverse reference tables editable by the Power Platform admin role.

### 7.1 Tier × Zone → DLP policy group

```yaml
dlp_group_lookup:
  tier_1_zone_1: "Restricted-NPI-CustomerFacing"
  tier_1_zone_2: "Restricted-NPI"
  tier_1_zone_3: "Restricted-NPI"            # rare combo, escalate
  tier_2_zone_1: "Regulated-Customer"
  tier_2_zone_2: "Regulated-General"
  tier_2_zone_3: "Regulated-General"
  tier_3_zone_1: "Personal-WithExternal"     # rare combo
  tier_3_zone_2: "Personal-Productivity"
  tier_3_zone_3: "Personal-Productivity"
```

### 7.2 Tier → retention class

```yaml
retention_lookup:
  tier_1: { class: "regulated-7yr-WORM", purview_label: "FSI-Tier1-Records" }
  tier_2: { class: "regulated-7yr",       purview_label: "FSI-Regulated" }
  tier_3: { class: "default-7yr",         purview_label: "FSI-Default" }
```

### 7.3 Zone → Managed Environment requirement

```yaml
managed_env_lookup:
  zone_1: required
  zone_2: required
  zone_3: optional
```

### 7.4 Tier → MRM evidence requirements (firm policy per OCC 2026-13)

```yaml
mrm_evidence_lookup:
  tier_1:
    - "Holdout-test results on representative inputs (≥100 cases)"
    - "Red-team adversarial test report"
    - "Vendor attestation (if BYO LLM)"
    - "Sponsor + MRM committee written sign-off"
    - "Quarterly performance recertification"
  tier_2:
    - "Smoke-test results on 20+ representative inputs"
    - "Sponsor + Compliance written sign-off"
    - "Annual performance recertification"
  tier_3:
    - "Maker self-test confirmation"
    - "Sponsor sign-off (Teams card)"
```

### 7.5 Path → SLA targets

```yaml
sla_lookup:
  EXPRESS:  { sponsor_response: "1 business day", time_to_provision: "same day" }
  STANDARD: { sponsor_response: "2 business days", infosec_review: "5 business days",
              time_to_provision: "5 business days" }
  FULL:     { sponsor_response: "3 business days", parallel_reviews: "10 business days",
              mrm_committee: "next monthly meeting", time_to_provision: "20 business days" }
```

### 7.6 Path → InfoSec review intensity

```yaml
infosec_review_lookup:
  EXPRESS:  { mode: "passive_sample_log", target_sample_pct: 10, sla_days: 30 }
  STANDARD: { mode: "active_sample_review", target_sample_pct: 10, sla_days: 5 }
  FULL:     { mode: "100pct_review", sla_days: 5 }
```

### 7.7 Other policy lookups

| Lookup | Source | Frequency of update |
|---|---|---|
| Approved foundation models | Procurement + AI Governance Committee | Quarterly |
| Approved Power Platform connectors | InfoSec + Microsoft connector taxonomy | Monthly (sync from PPAC) |
| Approved knowledge-source SharePoint sites | Records + per-business-unit content owners | Per-request |
| Sovereign-cloud feature parity matrix | IT architecture | Per-feature when MS announces parity |
| AUP version | Legal | When Legal updates the policy |
| Disclosure language templates | Compliance + Legal | Annual review |
| Cost-center allocation table | Finance | Quarterly |

### 7.8 Why these are policy tables, not per-agent questions

Asking the maker "what DLP group should govern this environment?" (Claude's EP-010) violates principle #2 (maker types business intent, not governance jargon). The maker has no knowledge of DLP groups. The right answer is: tier and zone are computed from maker answers, then DLP group is looked up from the policy table. The maker never types "DLP group" — but the field still ends up populated on the decision pack.

---

## 8. System auto-detect spec (43 fields)

Per `catalog-evaluation-claude.md` Section 5. Brief recap with status:

| Confidence | Count | Sources |
|---|---|---|
| ✅ Confirmed working | 40 | Microsoft Graph v1, Power Platform Admin API, Azure RBAC, Entra Agent ID federated credentials |
| ⚠️ Needs spike verification | 3 | Purview catalog API path, Power Platform DLP `/policies` endpoint shape, Graph beta retentionLabels path |

**Pre-form-build action:** 30-minute API verification spike against a sandbox tenant. If a ⚠️ endpoint doesn't work as documented, mark the affected questions as "manual / Standard or Full path only" — the form should never claim auto-detect that fails silently.

**Auto-detect runs:**
- **At form open:** maker identity, manager (sponsor pre-fill), license, environment list, current connections in maker's default environment, sensitivity labels of any SharePoint site they pre-selected
- **At form submit:** Entra Agent ID workload identity creation, Sentinel rule template generation, decision-pack record commit
- **On maker action mid-form:** if maker picks a SharePoint site in E3 / S1, async lookup triggers `agent-knowledge-source-scanner`-style item-level perm scan; results presented to InfoSec reviewer at Stage 5

---

## 9. Dropped questions (~10) — explicit removals with rationale

These were in Claude's catalog but are removed from the form (and from the decision-pack record entirely, since they don't generate compliance evidence).

| ID | Question | Why dropped |
|---|---|---|
| EP-003 | Max users per month | Maker doesn't know; production telemetry is the right source. Capacity planning happens at provisioning time, not intake. |
| EP-004 | Conversation volume estimate | Same as EP-003. Pure speculation. |
| EP-008 | Dataverse storage estimate | 95% of makers pick "Unknown". Capacity is monitored at runtime via PPAC; oversized agents get throttling alerts that trigger remediation. |
| EP-012 | AI Builder credit estimate | Same as EP-008. Track actuals. |
| RT-007 | Business impact if unavailable 24h | Sponsor speculation. For Tier-1, DR posture is determined by tier policy (RTO <4hr); for Tier-2/3, "best effort." No middle ground that needs maker input. |
| BJ-009 | Training plan for users | Post-approval operational concern, not intake decision. |
| BJ-010 | Communications plan | Same — covered by sponsor + change management process if applicable. |
| BJ-011 | Feedback collection plan | All agents auto-collect feedback (computed field `feedback_collection = True`); maker doesn't choose. |
| BJ-005 (downgraded) | ROI quantification | Kept on Standard/Full as optional free-text (S7) but dropped from Express. ROI for a personal FAQ bot is a nuisance ask. |
| EP-006 | Which ALM stage (dev/test/prod) | All intake requests are dev-environment provisioning. Test and prod environments come from the ALM promotion request, not intake. Avoid double-asking. |

**Net catalog after drop:** 137 - 10 + 8 (Section 3 of evaluation, additions) = **135 fields on the decision-pack record.**

**Net maker-facing form questions across the three paths:**
- Express: 10
- Standard: 20
- Full: 35
- (Sponsor: 0 typed fields, 1 click + optional comment)

---

## 10. Decision-pack record schema — what lands in Dataverse

Even on Express path (where the maker types only 10 fields), the back-office record contains 135 fields populated like this:

| Source | Express path | Standard path | Full path |
|---|---|---|---|
| Maker direct entry | 10 | 20 | 35 |
| Sponsor entry (1 click + optional comment) | 1 | 1 | 1 |
| Reviewer entry (override only) | 0 (no review) | 0-2 (sample) | 0-10 |
| System auto-detect (Graph/PPAC/Purview) | 43 | 43 | 43 |
| System auto-classification (Section 6 rules) | 35 | 35 | 35 |
| System policy lookup (Section 7 tables) | 15 | 15 | 15 |
| Defaults / N/A (path-specific fields not asked) | 31 | 21 | 0 |
| **Total decision-pack fields** | **135** | **135** | **135** |

**FINRA 4511 / SEC 17a-4 evidence:** the record format is identical regardless of path. A regulator examining a Tier-3 Express-path agent sees the same 135-field record they'd see for a Tier-1 Full-path agent — including who approved it, when, what data sources were declared, which auto-classification rules fired, what overrides (if any) were applied. **The form path determines who typed what; it does not determine what evidence is retained.**

**Retention:** 7 years per locked decision #5. Stored with Purview retention label `FSI-AgentIntake-7yr` on the `IntakeRequest` Dataverse table + immutable export to ADLS Gen2 with WORM bucket policy for SEC 17a-4(f) compliance.

---

## 11. Adoption metrics & guardrails

### 11.1 Target adoption metrics (90-day post-launch)

| Metric | Target | Measurement |
|---|---|---|
| Express path % of total intakes | 60-70% | Intake DB query |
| Median maker time-to-submit (Express) | ≤ 4 minutes | Form telemetry |
| Median maker time-to-submit (Standard) | ≤ 10 minutes | Form telemetry |
| Median maker time-to-submit (Full) | ≤ 25 minutes | Form telemetry |
| Express auto-approval rate | ≥ 85% (sponsors approving) | Approval workflow |
| Sponsor median response time (Express) | ≤ 4 hours | Teams card telemetry |
| Voluntary intake submissions / shadow IT detection ratio | ≥ 5:1 | Cross-reference with `agent-registry-automation` discovery |
| Maker satisfaction (post-submit micro-survey) | ≥ 4.0 / 5.0 | Inline 5-point rating after submit |
| InfoSec review SLA hit rate (Standard 5-day, Full 10-day) | ≥ 90% | Review workflow telemetry |
| Decision-pack completeness (% of records with all 135 fields populated) | 100% (by definition) | Dataverse audit |

### 11.2 Guardrails — when to escalate Express → Standard or Full

Existing FSI-AgentGov solutions detect post-deployment drift and trigger re-intake:

| Solution | Drift signal | Action |
|---|---|---|
| `unrestricted-agent-sharing-detector` | Express agent shared beyond declared zone | Auto-quarantine + force re-intake at Standard or Full path |
| `scope-drift-monitor` | Agent reads data outside declared sources | Notify maker + sponsor + InfoSec; force re-intake within 14 days |
| `agent-access-monitor` | Permissions added beyond approval scope | Same |
| `agent-365-lifecycle-governance` | Sponsor departs firm | 60-day grace period for ownership transfer; otherwise deprovision |
| `unrestricted-agent-sharing-detector` (2nd rule) | Express agent's user count > 50 within 30 days | Auto-flag for re-intake (was misrouted as personal) |

### 11.3 Anti-gaming guardrails

The Express path has high adoption value but also high abuse potential. Guardrails to prevent makers from gaming the trigger questions:

1. **Maker cannot self-downgrade.** Once T2-T6 trigger Standard or Full, the form locks the path.
2. **Sponsor sees the trigger answers.** Sponsors approving an Express-path agent see explicitly what the maker declared (no NPI, no autonomous, etc.) and attest that this matches their understanding. Sponsor liability for misdeclaration is a meaningful deterrent.
3. **Sample audits with consequences.** Of the 10% Express-path agents InfoSec spot-audits, any misdeclared trigger answer triggers (a) retroactive escalation to the correct path, (b) notification to the sponsor, (c) maker temporary suspension from Express path for 90 days.
4. **Drift detection.** As above — declared scope vs. observed behavior is the catch-net.
5. **Annual recertification.** Every Express-path agent re-runs the 6 trigger questions at the 12-month mark; if any answer changes, the agent re-routes to the appropriate path.

---

## 12. Open questions (resolve before form build)

| # | Question | For | Blocks |
|---|---|---|---|
| OQ-A | Confirm Express auto-approve criteria match firm appetite. The locked decision (now amended) reads "Tier-3 + Zone-3 + no risk signals + sponsor sign-off." Some firms may want to also require zero external connectors or zero premium connectors for Express eligibility. | AI Governance Committee | Form trigger logic |
| OQ-B | Sample-audit % for Express path: is 10% the right rate? (Higher = more compliance assurance, lower throughput; lower = faster, more risk.) | InfoSec + Compliance | Section 7.6 policy table |
| OQ-C | Does the firm operate under NYDFS 23 NYCRR 500 amended cybersecurity rules? If yes, additional trigger question may be required for any agent processing covered data. | Legal / Compliance | Section 2 trigger set |
| OQ-D | Sovereign-cloud scope: is the firm in commercial M365, GCC, GCC-High, or DoD? If commercial-only, F12 (OH-013) can be dropped from Full path. | IT architecture | Section 5 question count |
| OQ-E | API verification spike: do the 3 ⚠️ endpoints (Purview catalog, PPAC `/policies`, Graph beta retentionLabels) work as Claude documented? | Developer (1-hour spike in sandbox tenant) | Section 8 auto-detect implementation |
| OQ-F | Microsoft Entra Agent ID Administrator role mis-scoping CVE referenced by Claude: independently verify before depending on it for A2A risk framing in F7/F8. | InfoSec | Section 5 F7/F8 rationale |
| OQ-G | OQ-001..010 from Claude's catalog (10 stakeholder questions for CPO, CCO, MRM Committee, etc.) — pilot-firm conversation needed to resolve. | Pilot-firm working group | Form go-live |
| OQ-H | Modification-of-existing-agent abbreviated track (S8 / BJ-013 new): what's the cutoff between "minor mod" (skip review) vs "major mod" (full re-review)? Suggested: any change to T1-T6 trigger answer = major; everything else = minor. | AI Governance Committee | Section 4 S8 routing |
| OQ-I | 90-day value review (S7): who runs it and what happens if expected outcome was not met? Sunset? Re-tier? Continue? | AI Governance Committee | Post-deployment workflow |
| OQ-J | Sponsor 1-click approval: is the adaptive card sufficient evidence for FINRA 3110 supervisory sign-off, or does the firm require attestation language that constitutes a "manual signature" per 17a-4(b)? | Compliance + Records | Sponsor card design |

---

## 13. What's deferred to Phase B form-build

Explicitly out of scope for this design document:

- Dataverse entity schema (already specified in `fit-assessment.md` Section 7 — 9 entities with `fsi_` prefix)
- Power Pages portal page layouts (per locked decision #3 — first surface to build)
- M365 Copilot declarative agent manifest (per locked decision #3 — second surface)
- Teams sponsor adaptive card JSON (per locked decision #3 — third surface; mocked in Section 3 only as illustrative)
- Sequence diagrams for the 7-stage workflow (in `fit-assessment.md`)
- Maker-voice UX copy beyond representative samples in this doc (need a content-design pass)
- Localization (English-US only at v1)
- Accessibility audit (WCAG 2.1 AA — required at form-build time)
- Power Automate flow JSON (per repository content policy: documentation only)
- Reviewer dashboard wireframes (Stage 5 review experience)
- API contracts for handoff to `agent-registry-automation` (per locked decision #2 — defined at handoff)
- Telemetry / metrics dashboard (Power BI report against `IntakeRequest` table)

---

## 14. Summary — by the numbers

| | |
|---|---|
| Maker form questions (Express) | **10** (6 triggers + 4) |
| Maker form questions (Standard) | **20** (6 triggers + 4 Express + 10) |
| Maker form questions (Full) | **35** (6 triggers + 4 Express + 10 Standard + 15) |
| Sponsor input | **1 click** + optional comment, all paths |
| Reviewer typing | **0** unless overriding (Standard 0-2, Full 0-10) |
| System auto-detect fields | **43** |
| System auto-classification fields | **35** |
| System policy-lookup fields | **15** |
| Decision-pack total fields | **135** (all paths) |
| Express path SLA | **Same business day** |
| Standard path SLA | **3-5 business days** |
| Full path SLA | **2-4 weeks** |
| Target Express path % of intakes | **60-70%** |
| Target Express maker time-to-submit | **≤ 4 minutes** |

**Key insight:** the maker types 10-35 things; the system records 135. This is the difference between a form that gets filled out and a form that gets routed around.

---

*End of design v1. Ready for stakeholder walkthrough; not yet a build spec.*
