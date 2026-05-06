# Architecture Decision Record — Agent Intake v0.2.0-preview

This ADR consolidates the locked product-owner decisions that shape the v0.2.0-preview MVP. The full reasoning and override paths live in [`research/04-open-questions-resolved.md`](../research/04-open-questions-resolved.md); this document is the shippable summary for customer admins, reviewers, and auditors.

> **All defaults are overridable** via [`templates/policy-lookup-tables.yaml`](../templates/policy-lookup-tables.yaml) without code changes.

---

## ADR-001 — Express path is the only path in v0.2-preview

**Decision:** v0.2.0-preview ships only the **Express path**: maker submits 10 questions, sponsor approves with one Teams click, system auto-provisions the agent identity. Standard and Full paths are deferred to v0.3 / v0.4.

**Why:** Shipping one full slice end-to-end produces real pilot data faster than shipping three half-built paths. The Express criteria are deliberately conservative (lowest tier + lowest zone + no risk signals), so the at-risk surface is narrow.

**Impact:** Higher-risk requests (any trigger answered Yes / Not sure, or audience above personal scope) are saved as drafts with a "use full intake when available" message. Customers must continue using their existing high-risk workflow until v0.3/v0.4.

---

## ADR-002 — Express eligibility = T1–T6 all "No" + Tier 3 + Zone 3

**Decision:** A request is Express-eligible if and only if **all six trigger questions are "No"** AND the resulting auto-classification is **Tier 3** (lowest under SR 11-7 mapping) AND **Zone 3** (Personal — lowest sensitivity).

**Why:** Each trigger maps to a regulatory or risk surface that warrants additional review (financial autonomy, MNPI/NPI, supervised activity, customer-facing, expanded data access, cross-border). Any single Yes warrants Standard or Full path. Tier and Zone gating prevents an Express path for team-scope or higher even when triggers are clean.

**Override:** `templates/policy-lookup-tables.yaml` → `auto_approve.additional_restrictions` to add further gates (e.g., disallow premium connectors).

---

## ADR-003 — 10% InfoSec passive sample on Express auto-approvals

**Decision:** Express auto-approvals are recorded with a passive InfoSec notification log. InfoSec samples **10%** weekly for retrospective review. sampling is manual against `fsi_intakerequest` filtered by `fsi_pathused = Express` and `fsi_decisionoutcome = AutoApproved`; the dashboard is deferred to v0.3.

**Why:** 10% balances assurance coverage against InfoSec workload and is consistent with NIST AI RMF and FFIEC AIO guidance for low-risk classes.

**Override:** `audit.sample_rate_express` (range 0.05 to 1.0).

---

## ADR-004 — Sponsor SLA: 3 days first response, escalate at 7 days

**Decision:**

| Day | Event |
|---|---|
| 0 | Teams card sent to sponsor |
| 3 | Maker reminded that response is due |
| 4 | First reminder to sponsor |
| 7 | Auto-escalate to sponsor's manager (Graph `/manager` lookup) |
| 11 | Final denial with reason "no sponsor response" |

**Why:** 3 days is short enough to feel responsive to makers; 7 days is long enough to absorb normal travel/PTO before escalation. Aligns with how firms typically supervise low-risk activity flows.

**Override:** `sponsor.sla_first_response_days`, `sponsor.escalate_after_days`, `sponsor.final_denial_after_days`.

---

## ADR-005 — Default-deny when maker country differs from data residency country

**Decision:** If the maker's working country (from Entra ID profile) differs from the declared data residency country of any data source the agent will use, the request defaults to **denied** with reason "cross-border data routing requires Privacy review". A Privacy reviewer can override.

**Why:** Cross-border data flows are a primary GDPR / Schrems II / sovereign-cloud risk surface. A conservative default protects customers who have not yet built a Privacy review function; those that have can override per request.

**Override:** `cross_border.default_action` (`deny` | `flag_for_review` | `allow`); `cross_border.privacy_override_role`.

---

## ADR-006 — 7-year immutable retention via Purview `FSI-AgentIntake-7yr` label

**Decision:** Every decision-log row (`fsi_intakedecisionlog`) is stamped with the Purview retention label `FSI-AgentIntake-7yr`. Records are immutable for 7 years.

**Why:** Covers FINRA Rule 4511 (6-year minimum), SEC Rule 17a-4 (3- and 6-year requirements with the 2022 WORM amendment allowing audit-trail electronic recordkeeping), CFTC Rule 1.31 (5-year minimum extending in some classes), and GLBA 501(b) record-keeping expectations. 7 years is the conservative envelope used across all four regimes.

**Override:** Label name and retention duration in the Purview portal. Update `templates/policy-lookup-tables.yaml` → `retention.label_name` to match.

---

## ADR-007 — Sponsor 1-click is sufficient FINRA 3110 evidence for Express only

**Decision:** For Express-path requests (Tier 3 + Zone 3 + no triggers), the sponsor's 1-click approval in the Teams adaptive card with attestation language is recognized as sufficient FINRA 3110 supervisory evidence. Tier-1/2 paths in v0.3/v0.4 will require additional reviewer evidence (InfoSec, Compliance, Legal, MRM where applicable).

**Why:** FINRA 3110 requires evidence of supervisory review *proportional to risk*. For the lowest-risk class, a documented attestation by the accountable supervisor with timestamp, identity, and rendered card content captured immutably is consistent with how firms supervise comparable low-risk activities (e.g., personal-trading auto-approvals).

**Override:** Attestation text in `templates/sponsor-approval-card.json`. Customers in NY DFS or international jurisdictions may extend the language.

---

## ADR-008 — Sponsor cannot self-approve

**Decision:** The sponsor must be a **different person** from the maker. The portal blocks the submission if maker and sponsor are the same Entra ID. Even for personal-zone agents, a separate supervisor click is required.

**Why:** Segregation of duties is a foundational supervisory principle. Allowing self-sponsorship even for low-risk agents would create a path that bypasses any human review.

**Override:** None for this preview. (No legitimate use case identified.)

---

## ADR-009 — Major modification triggers fresh review; minor does not

**Decision:** A change to **any of T1–T6** (or T7 if NYDFS enabled) after submission is a **major** modification that triggers fresh classification, new sponsor card, and new reviewer routing. A change to descriptive fields (business justification text, expected user count, named connectors within the same DLP classification) is a **minor** modification — sponsor 1-click re-confirm only.

**Why:** Trigger questions are by definition the questions that drive path and routing. Their change invalidates the prior decision pack as the supervisory record. Descriptive changes preserve the basis of the original decision.

**Override:** `modification.major_trigger_fields` array.

---

## ADR-010 — Denial appeal: one re-submission allowed

**Decision:** A maker whose request is denied may re-submit **once** (with a new sponsor or corrected answers). A second denial is final until firm policy changes or circumstances are materially different. Both denial events are retained immutably.

**Why:** Allows recovery from honest first-pass mistakes (wrong sponsor, misunderstood trigger) without enabling endless re-submission to "shop" for an approval.

**Override:** `appeal.max_resubmissions`.

---

## OCC 2026-13 framing note

This solution supports your firm's **firm-level governance** of AI agents. It does not assert formal Model Risk Management compliance against OCC Bulletin 2011-12 because that bulletin was rescinded by **OCC Bulletin 2026-13 (April 17, 2026)**, which explicitly excludes generative and agentic AI from formal MRM scope while reserving firm-level governance expectations. Where firms voluntarily extend MRM-style rigor (e.g., Tier-1 agents under v0.3), the design accommodates parallel reviewer routing and validation evidence capture.

The Federal Reserve **SR 11-7** principles remain operative for the firms that fall under Federal Reserve supervision and continue to inform tiering and reviewer composition.

---

## Source

Full reasoning, alternatives considered, and detailed override syntax: [`research/04-open-questions-resolved.md`](../research/04-open-questions-resolved.md).
