# Open Questions — Product Owner Resolutions

**Date:** 2026-05-02
**Owner:** Product owner (pre-Phase B)
**Status:** Defaults locked. Customers may override during pilot.

This document resolves the 10 open design questions (OQ-A through OQ-J) raised during Phase A and Phase B-prep, plus 7 stakeholder questions deferred from the catalog evaluation. Defaults are pragmatic and intentionally conservative; each is overridable per customer pilot.

---

## OQ-A — Express auto-approve criteria firmness

**Question:** Locked decision #1 says "Tier-3 + Zone-3 + no risk signal → sponsor sign-off only". Should we add additional restrictions (e.g., no premium connectors, no custom code)?

**Decision:** **No additional restrictions.** Auto-approve criteria for Express path:
- Risk tier = 3 (lowest, per SR 11-7 mapping)
- Zone = 3 (Personal, lowest sensitivity)
- All trigger questions T1-T6 = `No`
- Sponsor approves (1-click in Teams adaptive card within 5 business days)
- Maker is in good standing (active Entra ID account, not on a suppressed list — checked at submission)

**Rationale:** Adding premium-connector or custom-code restrictions would push at-most-15% of intakes from Express to Standard for marginal additional risk reduction. DLP policies already gate connector usage at runtime regardless of intake path. Custom code in Agent Builder is not currently possible; in Copilot Studio it requires a Power Fx skill that is governed by environment-level Managed-Env policies.

**Customer override path:** `templates/policy-lookup-tables.yaml` → `auto_approve.additional_restrictions` array. Add `"premium_connectors_disallowed"` or `"custom_code_disallowed"` to extend.

---

## OQ-B — InfoSec sample-audit percentage

**Question:** Express auto-approves with passive InfoSec notification logged for sampling. What % of auto-approved intakes should InfoSec sample-audit?

**Decision:** **10% sample rate for v0.1.** Sampling done weekly via the InfoSec sample-audit dashboard (deferred to v0.2). For v0.1 the passive log is recorded; sample selection is manual from the `fsi_intakerequest` table filtered by `fsi_pathused='express' AND fsi_decision='auto_approved'` with `RAND() < 0.1`.

**Rationale:** 10% balances coverage against InfoSec workload. NIST AI RMF and FFIEC AIO guidance both reference sample-based assurance as acceptable for low-risk classes. Sample size is configurable.

**Customer override path:** `templates/policy-lookup-tables.yaml` → `audit.sample_rate_express`. Range: 0.05 to 1.0.

---

## OQ-C — NYDFS scope

**Question:** Should the catalog include NYDFS 23 NYCRR 500 §500.11 third-party AI governance triggers as a default trigger question?

**Decision:** **No, not in default Express MVP.** Default assumption is the customer is not NYDFS-regulated. Customers who are (any insurance/banking/financial-services entity licensed by NY DFS) add an additional trigger T7 (`Will this agent process NY-resident customer data?`) which routes any `Yes` to Standard or Full path.

**Rationale:** NYDFS scope is customer-specific. Including it by default would push out-of-scope customers into unnecessary review. Override is one config line.

**Customer override path:** `templates/policy-lookup-tables.yaml` → `triggers.nydfs_enabled: true`.

---

## OQ-D — Sovereign cloud support

**Question:** Should v0.1 support GCC, GCC-High, DoD, or other sovereign clouds out of the box?

**Decision:** **Commercial M365 only for v0.1.** GCC / GCC-High / DoD customers must adapt:
- Replace Graph host (`graph.microsoft.com` → `graph.microsoft.us`)
- Replace BAP host (`api.bap.microsoft.com` → `api.gov.bap.microsoft.us` / `.gov-mil.bap.microsoft.us`)
- Verify Entra Agent ID feature availability in target cloud (currently GA in commercial; sovereign GA dates per Microsoft roadmap)
- Verify Purview availability (DoD has different SKU)

**Rationale:** Sovereign cloud testing requires tenant access in each cloud (we have none). Commercial-first ships value to the broadest customer set. Sovereign adaptation is mechanical (host strings) but must be customer-validated.

**Customer override path:** Document in `docs/sovereign-cloud-adaptation.md` (deferred to v0.2 unless pilot customer requires). For v0.1, all endpoint hosts are configurable via environment variables in scripts.

---

## OQ-E — API endpoint verification

**Question:** Three endpoints flagged for verification before reliance.

**Decision:** **Resolved by spike** — see `04-api-verification-spike.md`. Summary:
- Graph `/me` + `/me/manager` ✅ verified
- PPAC environments ✅ verified
- PPAC DLP `/v2/policies` ✅ verified (path corrected from original `/policies`)
- Graph beta `retentionLabels` ⚠️ requires admin role; one-time setup script approach adopted
- Purview catalog `/datamap/api` ⚠️ not verified (no Purview in spike sub); manual fallback for Express

---

## OQ-F — Entra Agent ID Administrator role CVE

**Question:** CSO Online (April 2026) reported a mis-scoping issue with the Entra Agent ID Administrator role. How should the design treat this?

**Decision:** **Cite as advisory; do not depend on it for design integrity.** The MVP uses `AgentIdentity.ReadWrite.All` (application permission) for the handoff script, granted via admin consent. The CVE concerns over-broad delegated permissions for the Agent ID Administrator role; it does not affect application-permission flows.

**Rationale:** Application permissions with managed identity are the recommended pattern (per repo policy: "managed-identity-first; client secrets are dev-only legacy"). The CVE is real but tangential; if Microsoft narrows the role scope post-GA, the script continues to work without change because it uses application permissions, not the role.

**Customer override path:** None needed. Document the CVE link in `docs/security-advisories.md` for transparency.

---

## OQ-G — Catalog open questions OQ-001..010

**Question:** The 137-question catalog raised 10 questions for pilot-firm conversation (e.g., MNPI handling specifics, parallel-vs-serial review thresholds, model-validation cadence).

**Decision:** **Defer to pilot-firm conversation.** For each, document the PO default in `docs/pilot-customization-guide.md` (Phase B deliverable):

| ID | Topic | PO default for v0.1 |
|---|---|---|
| OQ-001 | MNPI handling | Trigger T2 = MNPI question routes to Full path; broker-dealer sponsor + Compliance + Legal review |
| OQ-002 | Parallel review threshold | All Full-path reviews are parallel (not serial); locked decision per Phase A |
| OQ-003 | Model validation cadence | Annual for Tier-1; bi-annual for Tier-2; sample-based for Tier-3 |
| OQ-004 | MRM tier override authority | Chief Risk Officer (or delegate) can manually re-tier with written justification logged |
| OQ-005 | Cross-border data routing | Default deny if maker country ≠ data residency country; Privacy reviewer can override |
| OQ-006 | Customer-facing escalation | Any customer-facing agent (T4=Yes) → Full path; Marketing + Legal + Compliance required |
| OQ-007 | Connector inventory authority | Maker declares; PPAC DLP simulation gates approval; reviewer can require Purview augmentation |
| OQ-008 | Records-retention class for denied intakes | 3 years (FINRA 4511 minimum for supervision artifacts); auto-purged thereafter |
| OQ-009 | Sponsor reauthorization cadence | Annual sponsor re-attestation for any continuing agent; auto-reminder via Teams |
| OQ-010 | Decommissioning trigger | 90-day inactivity OR sponsor revocation OR Compliance order; routed via `agent-365-lifecycle-governance` |

**Customer override path:** `templates/policy-lookup-tables.yaml` keys per row. Each is a single config line.

---

## OQ-H — Modification cutoff between minor and major

**Question:** When a maker modifies a submitted intake, when does the modification trigger a fresh review (major) vs. a sponsor re-confirm only (minor)?

**Decision:** **Trigger-question-driven cutoff.** Any change to T1-T6 (or the T7 if NYDFS enabled) = **major** (full re-review including new sponsor and reviewer routing). Any change to descriptive fields (business justification text, expected user count, named connectors within the same DLP classification) = **minor** (sponsor 1-click re-confirm; reviewers notified but not re-routed).

**Rationale:** T1-T6 are by definition the questions that determine path and routing; any change there means the prior decision-pack is no longer valid as the supervisory record. Descriptive changes preserve the decision basis.

**Customer override path:** `templates/policy-lookup-tables.yaml` → `modification.major_trigger_fields`. Add or remove field IDs as needed.

---

## OQ-I — 90-day value review

**Question:** Who owns the 90-day post-deployment value review and what are the possible outcomes?

**Decision:** **AI Governance Committee owns.** Outcomes:
1. **Continue** — agent meets stated business outcomes; no changes
2. **Re-tier** — agent's actual usage pattern differs from intake declaration; new tier assigned, new reviewers if escalating
3. **Sunset** — agent has no usage, or business outcome not realized, or risk profile increased; decommissioning triggered via `agent-365-lifecycle-governance`

Review uses telemetry from `agent-observability-foundation` and `copilot-studio-analytics`. No new instrumentation needed for Express MVP; review is a quarterly batch process.

**Customer override path:** `templates/policy-lookup-tables.yaml` → `value_review.cadence_days`, `value_review.owner_group`. Express MVP uses defaults.

---

## OQ-J — Sponsor 1-click as FINRA 3110 sufficiency

**Question:** Does the sponsor's 1-click approval in the Teams card meet FINRA Rule 3110 supervision evidence requirements?

**Decision:** **Yes, for Express path (Tier-3 + Zone-3 + no risk signals).** The sponsor card includes:
- Attestation language: *"By approving, you confirm this agent's purpose, data sources, and intended users align with our supervisory expectations under FINRA Rule 3110, and that you accept ongoing supervisory accountability."*
- Capture of the click event with timestamp, sponsor Entra ID, IP address, and the rendered card content (immutable in `fsi_intakedecisionlog`)
- Retention of 7 years per OQ-008 default (covers FINRA 4511 + SEC 17a-4)

**Rationale:** FINRA 3110 requires *evidence* of supervisory review proportional to risk. For the lowest-risk class (Tier-3, Zone-3, no signals) a documented 1-click attestation by an accountable supervisor is consistent with how firms already supervise low-risk activities (e.g., Personal Trading System auto-approvals). For Tier-1/2 paths the sponsor click is necessary but not sufficient — InfoSec/Compliance/Legal review evidence is also captured.

**Customer override path:** Counsel-specific attestation language editable in `templates/sponsor-approval-card.json` → `attestation_text` field. Customers in regulated NY-DFS or international jurisdictions may extend the language without code changes.

---

## Stakeholder questions deferred from catalog evaluation

These 7 came up during Phase A and were noted as "answer with pilot firm". Defaults below.

| # | Question | Default for v0.1 |
|---|---|---|
| 1 | Sponsor must be a Registered Principal? | No for Express; Yes for Standard/Full when broker-dealer. Configurable. |
| 2 | Can a maker self-sponsor for personal-zone agents? | No. Sponsor must be a different person from the maker. |
| 3 | Can a Sponsor delegate the click? | Yes via Entra ID delegated reviewer; documented in `docs/sponsor-delegation.md` (v0.2). |
| 4 | Does an intake auto-create a registry entry on approval? | Yes — handoff script writes to `agent-registry-automation` Dataverse table. |
| 5 | Does the Express path require business justification text or is structured-only enough? | Structured-only is enough (BJ-001 dropdown of business outcomes); free-text is optional. |
| 6 | Is there a denial appeal path? | Yes — denied maker can re-submit once with new sponsor; second denial is final until policy changes. |
| 7 | What if the sponsor doesn't respond in 5 business days? | Auto-escalate to sponsor's manager (Graph `/manager` lookup); after another 5 days, denial with "no sponsor response" reason. |

All seven are configurable via `templates/policy-lookup-tables.yaml` for customers with different policies.

---

## Summary

- 10 OQs resolved with PO defaults
- 7 stakeholder questions resolved with PO defaults
- All defaults overridable via `templates/policy-lookup-tables.yaml` (single YAML per customer)
- No defaults block MVP build; Phase B can proceed
