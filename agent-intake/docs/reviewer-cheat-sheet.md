# Reviewer cheat-sheet — Standard and Full paths

**Audience:** InfoSec, Privacy, Compliance, Legal, and Model Risk Management (MRM) reviewers on the parallel review board.

**Purpose:** A practical operating guide for what you are attesting to, what evidence to gather, how quorum works, and when to approve, condition, deny, or recuse.

Use this guide with [`classification-rules.md`](./classification-rules.md), [`reviewer-app-build.md`](./reviewer-app-build.md), [`flow-configuration.md`](./flow-configuration.md), [`mrm-integration.md`](./mrm-integration.md), and [`decisions.md`](./decisions.md).

## Shared mechanics

### Quorum rules by tier

The shipped defaults come from [`classification-rules.md`](./classification-rules.md#reviewer-quorum-defaults) and `templates/policy-lookup-tables.yaml`.

| Tier | Default reviewer model | Default quorum | What it means operationally |
|---|---|---|---|
| **Tier 3 / Express** | Sponsor only | 1 of 1 | No reviewer board; use this row only as context for escalations |
| **Tier 2 / Standard** | Parallel reviewer board | 2 of 3 | InfoSec + Privacy by default, with Compliance added when the request triggers NPI or policy-based supervisory review |
| **Tier 1 / Full** | Parallel reviewer board | 3 of 5 | InfoSec, Privacy, Compliance, Legal, and MRM are the default board |

### Important Tier-1 note

For Tier 1, the shipped workflow treats quorum and MRM as related but not identical:

- the board usually reaches a **3-of-5** non-MRM quorum first
- the request can still remain **InReview** while the MRM handoff completes
- MRM is therefore a required downstream governance step for Full / Tier-1 scenarios, even when three approvals already exist

See [`flow-configuration.md`](./flow-configuration.md#flow-7-fsi-intake-mrm-handoff) and [`mrm-integration.md`](./mrm-integration.md).

### The Teams notification card you will receive

The reviewer card is defined in [`../templates/reviewer-notification-card.json`](../templates/reviewer-notification-card.json). The card is designed for fast triage.

Use the card for:

- request ID confirmation
- role confirmation
- due date check
- quick decision when the case is simple
- jumping into the reviewer app when the case needs full context

The card shows:

- request ID
- agent name
- maker name and UPN
- intended audience
- submitted time
- tier / zone
- routed path
- reviewer role
- due date
- quorum requirement
- business justification
- declared data-source summary
- role-specific attestation text
- actions: **Approve**, **Approve with conditions**, **Deny**, **Open in reviewer app**

### Teams card versus reviewer app

| Use Teams when... | Open the reviewer app when... |
|---|---|
| The case is straightforward and the evidence summary is enough | You need the full request context or linked evidence |
| You already know the control pattern for this use case | You need to compare the request, audit trail, and prior decisions |
| You can clearly approve, condition, or deny from the card | You need to inspect queue views, data sources, or other reviewer actions |

### The model-driven reviewer app

The reviewer app is the operating surface for deeper review. The baseline views are documented in [`reviewer-app-build.md`](./reviewer-app-build.md#4-views).

Start with these views:

| View | When to use it |
|---|---|
| **My open reviews** | Your day-to-day work queue |
| **Awaiting my role - <Role>** | Role-specific triage if your team works from a shared queue |
| **All Standard requests in queue** | Governance-lead or cross-role coordination |
| **All Full requests in queue** | Highest-friction and enterprise cases |
| **MRM queue** | Tier-1 cases that need model-risk follow-through |
| **Approved with conditions** | Follow-up and closure tracking |
| **Denied** | Pattern review, audit prep, and appeal context |

### Approve / Approve with conditions / Deny / Recuse

| Outcome | When to use it | Important rule |
|---|---|---|
| **Approve** | The request meets your role's standard as submitted | Add notes if they help later audit reconstruction |
| **Approve with conditions** | The request can proceed only if your conditions are met | `fsi_conditionstext` is required |
| **Deny** | The request is unsafe, incomplete, out of policy, or wrongly routed | A denial ends the request immediately in the shipped flow |
| **Recuse** | You cannot make an independent decision | Recusals do not count for or against approval; if they make quorum impossible, the request escalates |

Good conditions are:

- specific
- testable
- attributable to a named owner or team
- time-bound where possible

Weak conditions are statements like “be careful,” “monitor more,” or “review later” with no owner.

### SLA expectations and escalation paths

The shipped defaults come from `templates/policy-lookup-tables.yaml > reviewer_routing` and should be replaced with customer mailboxes before go-live.

| Role | Default SLA (business days) | Default escalation contact |
|---|---:|---|
| InfoSec | 5 | `infosec-escalations@contoso.com` |
| Privacy | 5 | `privacy-escalations@contoso.com` |
| Compliance | 5 | `compliance-escalations@contoso.com` |
| Legal | 7 | `legal-escalations@contoso.com` |
| MRM | 10 | `mrm-escalations@contoso.com` |

If you cannot meet the SLA:

1. recuse early if the conflict is structural
2. escalate early if the evidence is missing and another team must supply it
3. leave a note that tells the next reviewer exactly what is blocked

### Audit trail: what is written when you decide

Your decision is preserved across several records:

- `fsi_intakereview` — your role, outcome, notes, conditions, timestamps
- `fsi_intakeapproval` — optional per-approver evidence row
- `fsi_intakeauditevent` — queueing, decision, quorum, denial, escalation, or handoff events
- `fsi_intakedecisionlog` — immutable decision pack used for long-term reconstruction

That audit trail helps firms preserve proportional evidence for FINRA Rule 3110 supervision, FINRA Rule 4511(a), SEC Rules 17a-3(a)(17) and 17a-4(f), and CFTC Rule 1.31 when paired with the tenant's retention settings and decision-pack labeling.

## InfoSec reviewer

### What you are attesting to

You are attesting that the proposed access path, environment posture, connector usage, and monitoring design are acceptable for the stated tier and zone, subject to any conditions you record.

### Evidence checklist before deciding

Review at least these items:

- declared data sources and connector inventory
- requested audience and environment pattern
- whether the use case is autonomous or action-taking
- any write, delete, send, or external-post behavior
- managed-environment expectation from policy
- DLP connector group expectation from policy
- monitoring and kill-switch plan for Standard or Full cases
- any inter-agent routing or custom endpoint use

Primary references:

- [`classification-rules.md`](./classification-rules.md)
- [`flow-configuration.md`](./flow-configuration.md)
- [`drift-detection-integration.md`](./drift-detection-integration.md)

### Common patterns

**Approve** when the request is bounded, the access path is understandable, and the runtime controls match the risk tier.

**Common conditions** you may attach:

- keep rollout limited to the named team or department
- complete a quarterly access review before scope expansion
- keep the agent in a managed environment before production use
- remove premium or custom connectors until they are separately approved
- document the kill-switch owner for autonomous or action-taking paths

**Deny** when:

- the request hides or cannot explain connector scope
- the environment or access model is unmanaged for the stated risk tier
- there is no credible logging, monitoring, or shutdown story
- the maker is trying to use a higher-risk integration through a low-risk route

### Regulator backstop

InfoSec review often maps to a firm's safeguard obligations under GLBA Section 501(b), plus the operational-control expectations it associates with FINRA 25-07 and supervisory oversight under FINRA Rule 3110.

### When to recuse

Recuse when you:

- designed or approved the same exception you are now being asked to review
- own the target environment or integration and cannot act independently
- lack the technical context to evaluate the specific connector, API, or control pattern

## Privacy reviewer

### What you are attesting to

You are attesting that the declared personal-data use, residency posture, and privacy controls are acceptable for the stated business purpose, subject to any conditions you record.

### Evidence checklist before deciding

Review at least these items:

- whether T4 or T6 is positive or uncertain
- the declared data-residency country versus the maker's country
- the data-source summary and any personal-data categories
- expected output destinations and retention class
- whether a privacy impact assessment or equivalent internal review is needed
- whether cross-border transfer terms or an internal allow-list already exist

Primary references:

- [`classification-rules.md`](./classification-rules.md#cross-border-behavior-and-privacy-override)
- [`intake-questions-standard.md`](./intake-questions-standard.md)
- [`intake-questions-full.md`](./intake-questions-full.md)

### Common patterns

**Approve** when the data use is specific, the purpose is narrow, residency is understood, and the request matches an approved internal data pattern.

**Common conditions** you may attach:

- mask or remove fields not needed for the use case
- complete a DPIA or equivalent assessment before production go-live
- keep data in the named country or region
- retain outputs only under the approved class
- route any cross-border exception through the formal privacy override process

**Deny** when:

- the request cannot identify the data source or residency boundary
- the maker is asking for cross-border handling without an acceptable basis
- NPI or employee personal data is being used without a minimal-use explanation
- the request is vague enough that downstream controls cannot be validated

### Regulator backstop

Privacy review often maps to GLBA Section 501(b), the firm's privacy notice and processing obligations, and any state privacy program the firm has adopted. For cross-border scenarios, the review record also supports later explanation of why an override was or was not granted.

### When to recuse

Recuse when you:

- are the business owner of the same dataset and cannot review independently
- already granted a data-use exception that you are now being asked to validate
- need another privacy specialist because the jurisdiction or transfer pattern is outside your remit

## Compliance reviewer

### What you are attesting to

You are attesting that the use case, supervisory pattern, recordkeeping posture, and stated controls align with the firm's policy framework for the requested path.

### Evidence checklist before deciding

Review at least these items:

- business justification and intended audience
- whether the use case is customer-facing, advice-adjacent, or otherwise supervised activity
- recordkeeping implications of outputs and communications
- sponsor chain and accountability posture
- retention class and decision-pack completeness
- whether the request triggers a richer route because of MNPI, NPI, or external delivery

Primary references:

- [`decisions.md`](./decisions.md)
- [`flow-configuration.md`](./flow-configuration.md#flow-8-fsi-intake-decision-pack-writer)
- [`drift-detection-integration.md`](./drift-detection-integration.md)

### Common patterns

**Approve** when the case clearly fits internal productivity or the board has enough supervisory evidence for the broader use case.

**Common conditions** you may attach:

- require a named supervisory sampling plan before broad rollout
- keep the use case limited to the named team until a follow-up review completes
- add disclosure, escalation, or records steps for external or customer-adjacent usage
- document regulator-notification thresholds before go-live for Tier-1 cases

**Deny** when:

- the use case resembles regulated advice, order handling, or recordable communications without the supporting controls
- the request is routed too low for the actual audience or data type
- the decision-pack evidence would not be enough to explain the approval later

### Regulator backstop

Compliance review typically maps most directly to FINRA Rule 3110, FINRA Rule 4511(a), SEC Rule 17a-3(a)(17), SEC Rule 17a-4(f), CFTC Rule 1.31, and the firm's governance interpretation of FINRA 25-07.

### When to recuse

Recuse when you:

- are also the sponsor or business owner for the request
- previously directed the maker to use a specific path and cannot review independently
- need another compliance specialist because the product line or regulator domain is outside your coverage

## Legal reviewer

### What you are attesting to

You are attesting that the legal, contractual, disclosure, and vendor-risk posture is acceptable for the stated use case.

### Evidence checklist before deciding

Review at least these items:

- whether the agent is customer-facing or external-facing
- any third-party model, API, or vendor in the stack
- the contractual rights for data use, outputs, and retention
- cross-border transfer terms where relevant
- customer disclosure or consent language where relevant
- regulator-notification language for material incidents where the use case calls for it

Primary references:

- [`intake-questions-full.md`](./intake-questions-full.md)
- [`mrm-integration.md`](./mrm-integration.md)
- [`flow-configuration.md`](./flow-configuration.md)

### Common patterns

**Approve** when the request stays inside known internal terms or a clearly reviewed vendor posture.

**Conditions** are usually not the default legal outcome in the bundled policy because `conditional_approval_allowed` is set to `false` for Legal in `templates/policy-lookup-tables.yaml`. If your customer changes that policy, keep conditions specific and contractual.

**Deny** when:

- vendor terms do not support the proposed use
- external disclosures are required but not ready
- cross-border handling lacks the necessary legal basis
- liability, licensing, or data-rights assumptions are unresolved

### Regulator backstop

Legal review usually supports the firm's vendor, disclosure, and liability posture rather than a single standalone rule. In practice, it helps the board support the parts of FINRA Rule 3110, SEC Rule 17a-4(f), and the firm's AI-governance program that depend on accurate disclosures and enforceable terms.

### When to recuse

Recuse when you:

- are already acting as deal counsel for the same negotiation and cannot be independent
- need specialist counsel for a jurisdiction, product, or contract class outside your scope
- are being asked to sign off on a position you helped author without independent review

## MRM reviewer

### What you are attesting to

You are attesting that the request has the model-risk governance evidence your firm expects for the stated tier and handoff state.

### Evidence checklist before deciding

Review at least these items:

- materiality and decision-output type
- validation evidence, benchmark plan, or review plan
- monitoring cadence and drift-testing plan
- shutdown and resilience owner
- model provider and build source
- whether the request is Tier 1 and therefore routes to the MRM handoff described in [`mrm-integration.md`](./mrm-integration.md)

Primary references:

- [`mrm-integration.md`](./mrm-integration.md)
- [`intake-questions-full.md`](./intake-questions-full.md)
- [`flow-configuration.md`](./flow-configuration.md#flow-7-fsi-intake-mrm-handoff)

### Common patterns

**Approve** when the Tier-1 evidence is complete enough to continue into the downstream MRM workflow or when the case already satisfies your firm's model-governance expectations.

**Common conditions** you may attach:

- attach the validation report before production release
- set an annual review cadence or a tighter pilot cadence
- complete benchmark or champion/challenger testing before wider rollout
- define quantitative drift thresholds and responsible owners

**Deny** when:

- there is no named model owner or validation approach
- the use case affects financial decisions or controls without proportionate governance evidence
- the maker cannot explain the model source, monitoring plan, or shutdown path

### Regulator backstop

MRM review often uses the vocabulary of OCC Bulletin 2011-12 and Federal Reserve SR 11-7, even though this repository also points admins to the current framing note in [`decisions.md`](./decisions.md#occ-2026-13-framing-note). Use your firm's policy as the deciding authority for whether the request needs full model-risk treatment.

### When to recuse

Recuse when you:

- are the model owner, validator, or sponsor for the same request
- created the validation pack you are now being asked to approve
- need a different MRM reviewer because the model class or methodology is outside your assigned portfolio

## Reviewer closing checklist

Before you click a final outcome, make sure you can answer yes to these questions:

- Do I understand the use case and audience?
- Do I know which evidence I relied on?
- If I am conditioning the approval, is `fsi_conditionstext` specific enough to enforce later?
- If I am denying, have I written a reason the maker can act on?
- If I am recusing, have I made it clear who should review instead?

That discipline keeps the reviewer board fast, proportional, and easier to defend later.
